"""One row of features per emitted prediction, collected during the replay.

Phase 4 of the plan corrects the shipped model rather than replacing it, so
what it needs is not a new predictor but a table: for every prediction the
replay emitted, what the model said and what else was known at the moment it
said it. The second half is the whole constraint. A feature that was not
available at emit time cannot be used however well it predicts, so every column
here is read out of state the replay had already built by then - the vehicle's
track, the model's own evidence weights, the timetable - and nothing is looked
up afterwards.

Rows are appended from inside the same loop that fills `Result.buf`, one for
one and in the same order, so the target and the weight join by row index and
never by a key. `dataset` does that join.

Collecting them costs about a quarter of the replay's time - measured at 10.0 s
against 12.5 s over one hour of recording - so it is off unless asked for:

    python3 -m commuterlviv features --out reports/feats.npz
"""
import dataclasses
import datetime

import numpy as np

from .model import TZ, PaceModel
from .replay import _ratio

COLS = ("eta", "n_stops", "dist", "hour", "fix_age", "factor", "factor_age",
        "w_cell_fast", "w_cell_slow", "w_corr_fast", "route", "headway",
        "sched", "late")
DAY = 86400.0
TARGET_CLIP = 1.5    # log ratio: the truth is between a fifth and five times


class Features:
    """The feature table, filled one vehicle-epoch at a time."""

    def __init__(self, net, cap=1 << 20):
        self.a = np.empty((cap, len(COLS)), dtype=np.float32)
        self.n = 0
        self.route = _route_index(net)
        self.headway = _headways(net)

    def refresh(self, model, now):
        """What the whole epoch shares: the clock, and the model's evidence.

        How much the model actually knows about the road ahead is three running
        sums over cells, so that a span of it costs one subtraction per
        prediction rather than a walk. They are weights, not means: the means
        are already inside the ETA, and what a correction needs to know is how
        much the ETA was worth believing.
        """
        if not isinstance(model, PaceModel):
            raise SystemExit("features are collected from the pace model's own "
                             "evidence weights, which only `full` and its "
                             f"neighbours have; `{model.cfg.name}` has none")
        self.model = model
        self.hour = model._hours(now)
        self.day = datetime.datetime.fromtimestamp(now, TZ).replace(
            hour=0, minute=0, second=0, microsecond=0).timestamp()
        p = model.pace
        self.w = [_cum(model, w[model.unit]) for w in
                  (p.cf.read(now)[1], p.cs.read(now)[1])]
        self.w.append(_cum(model, p.rf.read(now)[1][model.cell_corr]))

    def add(self, tr, veh, now, s_now, stops, dt, offset):
        d1 = tr.sdist[stops]
        dist = np.maximum(d1 - s_now, 1.0)
        seen = offset.get(veh, (0.0, 0.0, -np.inf))[2]
        sched_now = float(np.interp(s_now, tr.sdist, tr.sched))
        cols = [dt,
                stops - tr.next_stop + 1.0,
                dist,
                np.full(len(dt), self.hour),
                np.full(len(dt), now - tr.ts),
                np.full(len(dt), _ratio(offset, veh)),
                np.full(len(dt), min(now - seen, DAY)),
                *[self.model.integrate(tr.shape_id, s_now, d1, w[0], w[1]) / dist
                  for w in self.w],
                np.full(len(dt), self.route.get(tr.trip, -1)),
                np.full(len(dt), self.headway.get(tr.trip, 0.0)),
                tr.sched[stops] - sched_now,
                np.full(len(dt), _wrap(now - self.day - sched_now))]

        k = len(dt)
        if self.n + k > len(self.a):
            grown = np.empty((max(2 * len(self.a), self.n + k), len(COLS)),
                             dtype=self.a.dtype)
            grown[:self.n] = self.a[:self.n]
            self.a = grown
        self.a[self.n:self.n + k] = np.stack(cols, axis=1)
        self.n += k

    def done(self):
        return self.a[:self.n]


def _cum(model, per_cell_weight):
    """A per-cell weight and its running sum, ready for `BaseModel.integrate`.

    Weights are per cell but a prediction spans a length of road, so what the
    integral has to return is a length-weighted mean: the weight is charged per
    metre here and divided by the distance again at the other end.
    """
    per_cell = per_cell_weight * model.cell_len
    cum = np.zeros(model.ncell + 1)
    np.cumsum(per_cell, out=cum[1:])
    return per_cell, cum


def _wrap(dt):
    """A difference of two clocks that may be on different service days."""
    return (dt + 0.5 * DAY) % DAY - 0.5 * DAY


def _route_index(net):
    """Route as a small integer, since a model cannot be handed a string."""
    order = {r: i for i, r in enumerate(sorted(set(net.trip_route.values())))}
    return {t: order[r] for t, r in net.trip_route.items()}


def _headways(net, window=3600.0):
    """How often this trip's own pattern runs, around the hour it runs at.

    A route every four minutes recovers from a delay by being overtaken by the
    next bus; a route every forty does not, and the two should not be expected
    to have the same residual. Measured from the timetable, so it is known
    before the day starts.
    """
    starts = {}
    for trip, key in net.pattern_of.items():
        starts.setdefault(key, []).append((net.trip_stops[trip][2][0], trip))
    out = {}
    for rows in starts.values():
        t = np.sort(np.array([r[0] for r in rows], dtype=float))
        for t0, trip in rows:
            near = t[np.abs(t - t0) <= window]
            out[trip] = float(np.median(np.diff(near))) if len(near) > 1 else 0.0
    return out


@dataclasses.dataclass
class Rows:
    """The feature table and everything needed to score a correction to it.

    `y` is the log of how much longer the crossing really took than the model
    said, so a correction is a multiplier and not a number of seconds - 30 s of
    optimism at a 40-minute horizon and at a 1-minute one are not the same
    mistake. It is clipped, so it cannot be inverted back to the arrival time
    and `t` carries that separately: a correction has to be scored in seconds
    against the crossing that really happened, tails included. `w` discounts a
    crossing interpolated across a wide gap between fixes, since where the truth
    itself is soft the residual is partly the truth's. `trip` is carried for the
    same reason `score.bootstrap` wants it: one late vehicle is one fact
    repeated at every stop ahead of it, not thirty independent ones.
    """

    x: np.ndarray
    y: np.ndarray
    w: np.ndarray
    at: np.ndarray
    event: np.ndarray
    t: np.ndarray
    trip: np.ndarray
    cols: tuple[str, ...] = COLS

    def __len__(self):
        return len(self.y)

    def col(self, name):
        return self.x[:, self.cols.index(name)]

    def select(self, mask):
        return dataclasses.replace(
            self, **{f.name: getattr(self, f.name)[mask]
                     for f in dataclasses.fields(self) if f.name != "cols"})

    @property
    def eta(self):
        """The model's own answer, in seconds ahead, as it was scored."""
        return np.maximum(self.col("eta"), 1.0)

    def error(self, correction=None):
        """Seconds early (negative) or late, with an optional log correction."""
        eta = self.eta if correction is None else self.eta * np.exp(correction)
        return self.at + eta - self.t

    def save(self, path):
        np.savez_compressed(
            path, cols=np.array(self.cols), x=self.x.astype(np.float32),
            y=self.y.astype(np.float32), w=self.w.astype(np.float32),
            at=self.at, event=self.event, t=self.t, trip=self.trip)


def load(path):
    d = np.load(path)
    return Rows(x=d["x"].astype(float), y=d["y"].astype(float),
                w=d["w"].astype(float), at=d["at"], event=d["event"],
                t=d["t"], trip=d["trip"],
                cols=tuple(str(c) for c in d["cols"]))


def dataset(res, feats, truth):
    """The rows a residual model is fitted on, joined to what actually happened."""
    from .predictors import event_of

    a = res.buf.done()
    x = feats.done()
    if len(x) != len(a):
        raise RuntimeError(f"{len(x)} feature rows against {len(a)} predictions")
    ev = event_of(res, truth)
    ok = ev >= 0
    ev, at = ev[ok], a["epoch"][ok] + res.t0
    x = x[ok]
    t = truth.time[ev]
    m = at < t
    ev, at, x, t = ev[m], at[m], x[m], t[m]

    eta = np.maximum(x[:, COLS.index("eta")].astype(float), 1.0)
    y = np.clip(np.log((t - at) / eta), -TARGET_CLIP, TARGET_CLIP)
    w = 1.0 / np.maximum(truth.gap[ev], 1.0)
    return Rows(x=x.astype(float), y=y, w=w / w.mean(), at=at, event=ev, t=t,
                trip=truth.trip[ev])


def dump(out, net=None, db=None, t_from=None, t_to=None, warmup=0.0):
    """Replay the shipped model once, keeping features as well as ETAs."""
    from . import config, network, replay
    from .truth import Truth

    net = net or network.load()
    feats = Features(net)
    kw = {} if db is None else {"db": db}
    _, res = replay.run(net, cfg=config.FULL, t_from=t_from, t_to=t_to,
                        warmup=warmup, feats=feats, progress=60, **kw)
    res.net = net
    truth = Truth(net, res)
    rows = dataset(res, feats, truth)
    rows.save(out)
    print(f"\n{len(rows)} rows x {len(COLS)} features from {truth.n} crossings "
          f"-> {out}")
    return rows
