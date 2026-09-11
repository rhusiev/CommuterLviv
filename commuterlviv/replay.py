"""Strictly causal replay of the recorded feed.

One forward pass in timestamp order. Per epoch (default 60 s), in this order:
fold arriving fixes into vehicle tracks, hand the resulting travel times to the
model, rebuild the cumulative travel-time table, then emit an ETA per remaining
stop. Observations are batched to the epoch boundary, which stays causal because
the model is only read after the batch is applied.
"""
import datetime
import os
import sqlite3

import numpy as np

from . import baselines, config, gtfs, track
from .model import PaceModel

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
            # on the absolute grid, so epochs line up with the recorded feeds'
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


def _idx(m, names, key):
    i = m.get(key)
    if i is None:
        i = m[key] = len(names)
        names.append(key)
    return i


def drain(model, tracks, closed, now, offset):
    """Hand the epoch's cell crossings, finished and in progress, to the model."""
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
        _residuals(parts, rows, exp, offset, now)
    keep = np.array([r is not None for r in rows])
    if not keep.any():
        return
    a = np.array([r for r in rows if r is not None], dtype=float)
    model.observe(idx[keep], a[:, 0], a[:, 1], a[:, 2], a[:, 3], now)


def _residuals(parts, rows, exp, offset, now, forget=0.9):
    """How fast each vehicle has been running against the road model, as two
    decaying sums so the ratio favours its recent crossings."""
    for (_, _, veh, _), r, e in zip(parts, rows, exp):
        if r is None:
            continue
        d, pace, hold, w = r
        if w <= 0.0:
            continue
        obs, ex, _ = offset.get(veh, (0.0, 0.0, -np.inf))
        offset[veh] = (obs * forget + (d * pace + hold) * w,
                       ex * forget + e * w, now)


def _ratio(offset, veh, k=60.0):
    """The vehicle's ratio, shrunk towards 1 until it has earned some weight."""
    obs, ex, _ = offset.get(veh, (0.0, 0.0, -np.inf))
    return (obs + k) / (ex + k) if ex > 0.0 else 1.0


def _factor(offset, veh, lo=0.6, hi=1.7):
    """The ratio as the ETA may use it, bounded: a vehicle just off a terminus
    would otherwise scale the whole trip by 3."""
    return float(np.clip(_ratio(offset, veh), lo, hi))


def _fade(dt, f, tau=300.0):
    """Apply a vehicle's speed ratio leg by leg, decaying with lead time: full
    ratio for the next stop, none of it for the far end."""
    inc = np.diff(dt, prepend=0.0)
    mid = dt - 0.5 * inc          # lead time at the middle of each leg
    return np.cumsum(inc * (1.0 + (f - 1.0) * np.exp(-mid / tau)))


def _lateness_eta(tr, s_now):
    """Seconds to each remaining stop under the official API's method: one
    lateness carried unchanged, so the answer is the scheduled travel time.

    Only differences of timetable times are taken, so the service day never has
    to be resolved.
    """
    sched_now = float(np.interp(s_now, tr.sdist, tr.sched))
    return np.maximum(tr.sched[tr.next_stop:] - sched_now, 0.0)


def prune(tracks, runs, now):
    """Forget vehicles that have gone quiet, so `tracks` stops growing.

    The run counter outlives the track: truth is keyed by it, so a returning
    vehicle must not reuse a number it has already spent.
    """
    dead = [v for v, t in tracks.items()
            if t.ts is None or now - t.ts > track.GAP_RESET]
    for veh in dead:
        runs[veh] = tracks.pop(veh).run


def predictable(tr, now):
    """Whether this track can be predicted from at all, without asking the model."""
    return (tr.ts is not None and tr.s is not None and now - tr.ts <= STALE
            and tr.next_stop < len(tr.sdist))


def believed(tr, now):
    """Where the vehicle is thought to be now: the last fix, dead reckoned, for
    at most EXTRAP seconds."""
    return min(tr.s + tr.v * min(now - tr.ts, EXTRAP), tr.shape.length)


def etas(model, tr, veh, now, offset):
    """This vehicle's remaining stops within the horizon, as of `now`.

    Returns `(next_stop, believed distance, seconds to each stop from next_stop
    on, which of those are inside the horizon)`, or None. Used by both the
    offline replay and the live service.
    """
    if not predictable(tr, now):
        return None
    i = tr.next_stop
    s_now = believed(tr, now)
    if model.cfg.eta == "lateness":
        dt = _lateness_eta(tr, s_now)
    else:
        dt = model.time_between(tr.shape_id, s_now, tr.sdist[i:])
        if model.cfg.vehicle_offset != "off":
            f = _factor(offset, veh)
            dt = (_fade(dt, f) if model.cfg.vehicle_offset == "decay"
                  else dt * f)
    k = np.nonzero(dt <= HORIZON)[0]
    return (i, s_now, dt, k) if len(k) else None


def _flush(model, res, tracks, runs, closed, now, veh_idx, trip_idx, emit=True,
           offset=None):
    # set before the drain, so the first scored epoch is past any training
    model.emitting = emit
    drain(model, tracks, closed, now, offset)
    res.epochs += 1
    prune(tracks, runs, now)
    if not emit:
        return
    model.refresh(now)
    ep = int(now - res.t0)
    for veh, tr in tracks.items():
        if not predictable(tr, now):
            continue
        # numbered before the model is consulted, so variants replaying the same
        # recording agree on event numbering
        vi = _idx(veh_idx, res.veh_ids, veh)
        ti = _idx(trip_idx, res.trip_ids, tr.trip)
        got = etas(model, tr, veh, now, offset)
        if got is None:
            continue
        i, s_now, dt, k = got
        res.pos.append((ep, vi, ti, tr.run, s_now))
        res.buf.extend(ep, vi, ti, tr.run, i + k,
                       np.rint(now - res.t0 + dt[k]).astype("i4"))
