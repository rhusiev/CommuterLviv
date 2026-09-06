"""Strictly causal replay of the recorded feed.

One forward pass in timestamp order. At any instant the model has seen only
what had already arrived by then, so the predictions it emits are honest -
nothing downstream can leak backwards into them.

Per epoch (default 60 s) the pass does four things, in this order:

  1. fold every fix that arrived during the epoch into its vehicle's track
  2. hand the resulting travel times - finished and in progress - to the model
  3. rebuild the cumulative travel-time table
  4. emit an ETA for every stop each vehicle has still to reach

Travel-time observations are batched to the epoch boundary rather than applied
one at a time. That is still causal - the model is only ever read at step 4,
after step 2 - and it replaces a few million tiny array updates with one
vectorised update per minute.
"""
import datetime
import hashlib
import multiprocessing
import os
import sqlite3
import time

import numpy as np

from . import baselines, config, gtfs, predictors, track
from .model import PaceModel
from .truth import Truth

DB = os.path.join(gtfs.DATA, "feed.db")
HORIZON = 45 * 60.0      # match the API's own forecast horizon
EPOCH = 60.0
STALE = 120.0            # s since last fix before a vehicle is dropped
EXTRAP = 60.0            # s of dead reckoning allowed at an epoch

DTYPE = np.dtype([("epoch", "i4"), ("veh", "i4"), ("trip", "i4"),
                  ("run", "i2"), ("stop_i", "i2"), ("eta", "i4")])


class NoData(Exception):
    """The requested window contains nothing to replay."""


def build(net, cfg=None):
    """The estimator a config asks for."""
    cfg = cfg or config.FULL
    if cfg.learn == "knn":
        return baselines.KnnModel(net, cfg)
    if cfg.learn == "median":
        return baselines.MedianModel(net, cfg)
    if cfg.learn.startswith("table"):
        return baselines.TableModel(net, cfg)
    return PaceModel(net, cfg)


def _window(t_from, t_to):
    """The replay window as local times, for an error a human has to read."""
    def when(t, unbounded):
        return (datetime.datetime.fromtimestamp(t).isoformat(" ", "seconds")
                if t else unbounded)
    return f"{when(t_from, 'the first fix')} .. {when(t_to, 'the last fix')}"


class Buf:
    """Append-only packed record array."""

    def __init__(self, cap=1 << 20):
        self.a = np.empty(cap, dtype=DTYPE)
        self.n = 0

    def extend(self, epoch, veh, trip, run, stop_i, eta):
        k = len(stop_i)
        if self.n + k > len(self.a):
            self.a = np.resize(self.a, max(len(self.a) * 2, self.n + k))
        s = slice(self.n, self.n + k)
        self.a["epoch"][s] = epoch
        self.a["veh"][s] = veh
        self.a["trip"][s] = trip
        self.a["run"][s] = run
        self.a["stop_i"][s] = stop_i
        self.a["eta"][s] = eta
        self.n += k

    def done(self):
        return self.a[:self.n]


class Result:
    def __init__(self, t0):
        self.t0 = t0
        self.buf = Buf()
        self.truth = {}      # (veh_idx, trip_idx, run, stop_i) -> crossing time
        self.gap = {}        # same key -> width of the interpolated interval
        self.pos = []        # (epoch, veh_idx, trip_idx, run, believed distance)
        self.veh_ids = []
        self.trip_ids = []
        self.epochs = 0


def run(net, t_from=None, t_to=None, epoch=EPOCH, db=DB, warmup=0.0,
        progress=None, model=None, cfg=None):
    model = model or build(net, cfg)
    offset = {} if model.cfg.vehicle_offset != "off" else None
    tracks = {}
    runs = {}
    closed = []
    veh_idx, trip_idx = {}, {}

    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    sql = ("SELECT veh_id, veh_ts, trip_id, lat, lon, speed, odometer FROM veh "
           "WHERE trip_id IS NOT NULL AND poll_ts - veh_ts BETWEEN -60 AND 300")
    args = []
    if t_from:
        sql += " AND veh_ts >= ?"
        args.append(t_from)
    if t_to:
        sql += " AND veh_ts <= ?"
        args.append(t_to)
    cur = con.execute(sql + " ORDER BY veh_ts", args)

    res = None
    next_epoch = t_start = None
    for veh, ts, trip, lat, lon, speed, odo in cur:
        if trip not in net.trip_stops:
            continue
        if res is None:
            t_start = float(ts)
            # On the absolute grid, so our epochs coincide with the ones the
            # recorded feeds are replayed at and the two can be paired.
            next_epoch = np.ceil(t_start / epoch) * epoch
            res = Result(t_start)
        while ts >= next_epoch:
            _flush(model, res, tracks, runs, closed, next_epoch, veh_idx,
                   trip_idx, emit=next_epoch - t_start >= warmup, offset=offset)
            next_epoch += epoch
            if progress and res.epochs % progress == 0:
                print(f"  t+{(next_epoch - t_start) / 60:5.0f} min  "
                      f"tracks {len(tracks):4d}  preds {res.buf.n}", flush=True)

        tr = tracks.get(veh)
        if tr is None:
            tr = tracks[veh] = track.Track(veh, runs.get(veh, 0))
        done, passings = track.observe(tr, net, float(ts), lat, lon,
                                       speed, odo, trip)
        if done:
            base = model.shape_base[tr.shape_id]
            closed.extend((base + c.i, c, veh) for c in done)
        if passings:
            vi = _idx(veh_idx, res.veh_ids, veh)
            ti = _idx(trip_idx, res.trip_ids, tr.trip)
            for i, t, gap in passings:
                k = (vi, ti, tr.run, i)
                if k not in res.truth:
                    res.truth[k] = t
                    res.gap[k] = gap

    con.close()
    if res is None:
        raise NoData(f"{db} holds no usable vehicle fixes in {_window(t_from, t_to)}. "
                     "The city runs no service between roughly 00:00 and 05:30, "
                     "so a window inside the nightly shutdown is empty by "
                     "construction rather than by any fault of the recording.")
    _flush(model, res, tracks, runs, closed, next_epoch, veh_idx, trip_idx,
           emit=True, offset=offset)
    return model, res


class Recording:
    """The part of a Result that does not depend on which variant produced it.

    A whole Result carries a few tens of megabytes of predictions and believed
    positions that only the process which produced them has any use for. What
    has to cross back between processes is what every variant agrees on: the
    crossings, and the numbering of vehicles and trips they are named by. That
    is also everything the three outside predictors need, so they are scored
    against this rather than against any one variant's replay.
    """

    __slots__ = ("truth", "gap", "trip_ids", "veh_ids", "epochs", "net")

    def __init__(self, res):
        self.truth = res.truth
        self.gap = res.gap
        self.trip_ids = res.trip_ids
        self.veh_ids = res.veh_ids
        self.epochs = res.epochs
        self.net = None   # not picklable in bulk; the parent puts it back


def _fingerprint(res):
    """A short check that two replays tracked the same crossings in the same order.

    Order matters as much as membership: the ground truth numbers its events by
    the order this dict was filled, so a worker's event 7 has to be the parent's
    event 7 as well.
    """
    return hashlib.blake2b(np.array(list(res.truth), dtype=np.int64).tobytes(),
                           digest_size=8).hexdigest()


_JOB = None   # (net, db, kw), set before forking so `net` is never pickled


def _replay_one(job):
    i, cfg = job
    net, db, kw = _JOB
    t = time.time()
    _, res = run(net, cfg=cfg, db=db, **kw)
    res.net = net
    series = predictors.ours(res, Truth(net, res))
    return (cfg.name, series, _fingerprint(res),
            Recording(res) if i == 0 else None, time.time() - t)


def run_many(net, cfgs, db=DB, workers=None, **kw):
    """Replay one recording under several configs, cold, in parallel.

    Tracking does not depend on the config. Every one of these replays rebuilds
    the same vehicle tracks from the same fixes, which is about three quarters
    of the work and is why a seventeen-variant comparison took the better part
    of an hour. The replays share nothing, so the way to stop paying for that
    seventeen times over is to pay in parallel.

    Workers are forked rather than spawned, so the network geometry is handed to
    them by the operating system instead of being pickled to each one. What
    comes back is one flattened predictor per config, not the replay Result:
    that is large and of no use outside the process that built it.

    Two cores are left free, for the collector and for whatever else is running.

    Returns (named, truth, recording).
    """
    global _JOB

    jobs = list(enumerate(cfgs))
    workers = workers or min(len(jobs), max(1, (os.cpu_count() or 3) - 2))
    _JOB = (net, db, kw)
    try:
        with multiprocessing.get_context("fork").Pool(workers) as pool:
            out = list(pool.imap(_replay_one, jobs, chunksize=1))
    finally:
        _JOB = None

    named = {}
    _, _, first, rec, _ = out[0]
    rec.net = net
    for name, series, fp, _, took in out:
        if fp != first:
            raise RuntimeError(f"{name} tracked a different set of crossings")
        named[name] = series
        print(f"  {name:<16} {len(series):>8} predictions  {took:5.1f}s", flush=True)
    return named, Truth(net, rec), rec


def _idx(m, names, key):
    i = m.get(key)
    if i is None:
        i = m[key] = len(names)
        names.append(key)
    return i


def _drain(model, tracks, closed, now, offset):
    """Hand the epoch's cell crossings to the model.

    Finished crossings report whatever weight they have left. Crossings still
    in progress report the part that has elapsed, so a vehicle stuck in a jam
    informs the model while it is stuck rather than once it is through.
    """
    parts = [(gi, c, veh, True) for gi, c, veh in closed]
    if model.cfg.incremental:
        parts += [(model.shape_base[t.shape_id] + t.cell.i, t.cell, veh, False)
                  for veh, t in tracks.items() if t.cell is not None]
    closed.clear()
    if not parts:
        return

    idx = np.array([p[0] for p in parts])
    exp = model.expected(idx)
    rows = [c.take(e, final) for (_, c, _, final), e in zip(parts, exp)]
    if offset is not None:
        _residuals(parts, rows, exp, offset)
    keep = np.array([r is not None for r in rows])
    if not keep.any():
        return
    a = np.array([r for r in rows if r is not None], dtype=float)
    model.observe(idx[keep], a[:, 0], a[:, 1], a[:, 2], a[:, 3], now)


def _residuals(parts, rows, exp, offset, forget=0.9):
    """How fast each vehicle has been running against the road model.

    Kept as two decaying sums so the ratio is a weighted mean over this
    vehicle's recent crossings rather than over its whole trip - a bus that was
    slow twenty minutes ago is weak evidence about the next stop.
    """
    for (_, _, veh, _), r, e in zip(parts, rows, exp):
        if r is None:
            continue
        d, pace, hold, w = r
        if w <= 0.0:
            continue
        obs, ex = offset.get(veh, (0.0, 0.0))
        offset[veh] = (obs * forget + (d * pace + hold) * w,
                       ex * forget + e * w)


def _factor(offset, veh, lo=0.6, hi=1.7, k=60.0):
    """The vehicle's ratio, shrunk towards 1 until it has earned some weight."""
    obs, ex = offset.get(veh, (0.0, 0.0))
    if ex <= 0.0:
        return 1.0
    return float(np.clip((obs + k) / (ex + k), lo, hi))


def _fade(dt, f, tau=300.0):
    """Apply a vehicle's speed ratio only as far along the path as it holds.

    Multiplying the whole remaining ETA by the ratio assumes a vehicle running
    30% slow now will still be running 30% slow in forty minutes. It will not:
    the autocorrelation of a vehicle's own ratio falls to 0.05 by twenty
    minutes, an e-folding time near 4.5 minutes.

    So the trip is corrected leg by leg. Each leg is scaled by however much of
    the ratio is still credible at the moment the vehicle would be driving it,
    which is the full ratio for the next stop and none of it for the far end.
    """
    inc = np.diff(dt, prepend=0.0)
    mid = dt - 0.5 * inc          # lead time at the middle of each leg
    return np.cumsum(inc * (1.0 + (f - 1.0) * np.exp(-mid / tau)))


def _lateness_eta(tr, s_now):
    """Seconds to each remaining stop under the official API's method.

    The road is not consulted at all. Where the vehicle is now says what time
    the timetable expected it to be there; the difference is one lateness, and
    it is carried unchanged to every stop still ahead.

    That lateness then cancels out of the wait, which is the whole point: this
    predictor's answer is the *scheduled* travel time from here on, no matter
    how late the vehicle is or what the traffic is doing. The service day never
    has to be worked out either, since only differences of timetable times are
    ever taken.
    """
    sched_now = float(np.interp(s_now, tr.sdist, tr.sched))
    return np.maximum(tr.sched[tr.next_stop:] - sched_now, 0.0)


def _prune(tracks, runs, now):
    """Forget vehicles that have gone quiet.

    A fix arriving more than GAP_RESET after the last one restarts the track
    anyway, so dropping it here changes no prediction. What it changes is that
    `tracks` stops growing for the life of the process, which over days would
    otherwise leave `_drain` walking thousands of vehicles that stopped
    reporting yesterday. The run counter outlives the track, because truth is
    keyed by it and a vehicle returning to the same trip must not reuse a
    number it has already spent.
    """
    dead = [v for v, t in tracks.items()
            if t.ts is None or now - t.ts > track.GAP_RESET]
    for veh in dead:
        runs[veh] = tracks.pop(veh).run


def _flush(model, res, tracks, runs, closed, now, veh_idx, trip_idx, emit=True,
           offset=None):
    # An estimator that fits once and freezes needs to know where the warmup
    # ends, and this is the only place that knows it. Set before the drain, so
    # the epoch that first scores is already past the estimator's training.
    model.emitting = emit
    _drain(model, tracks, closed, now, offset)
    res.epochs += 1
    _prune(tracks, runs, now)
    if not emit:
        return
    model.refresh(now)
    ep = int(now - res.t0)
    for veh, tr in tracks.items():
        if tr.ts is None or tr.s is None or now - tr.ts > STALE:
            continue
        i = tr.next_stop
        if i >= len(tr.sdist):
            continue
        # Numbered before anything the model says is consulted, so two variants
        # replaying the same recording agree on what event 7 is.
        vi = _idx(veh_idx, res.veh_ids, veh)
        ti = _idx(trip_idx, res.trip_ids, tr.trip)
        s_now = min(tr.s + tr.v * min(now - tr.ts, EXTRAP), tr.shape.length)
        if model.cfg.eta == "lateness":
            dt = _lateness_eta(tr, s_now)
        else:
            dt = model.time_between(tr.shape_id, s_now, tr.sdist[i:])
            if offset is not None:
                f = _factor(offset, veh)
                dt = (_fade(dt, f) if model.cfg.vehicle_offset == "decay"
                      else dt * f)
        k = np.nonzero(dt <= HORIZON)[0]
        if not len(k):
            continue
        res.pos.append((ep, vi, ti, tr.run, s_now))
        res.buf.extend(ep, vi, ti, tr.run, i + k,
                       np.rint(now - res.t0 + dt[k]).astype("i4"))
