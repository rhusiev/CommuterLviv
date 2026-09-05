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
import os
import sqlite3

import numpy as np

from . import gtfs, track
from .model import PaceModel

DB = os.path.join(gtfs.DATA, "feed.db")
HORIZON = 45 * 60.0      # match the API's own forecast horizon
EPOCH = 60.0
STALE = 120.0            # s since last fix before a vehicle is dropped
EXTRAP = 60.0            # s of dead reckoning allowed at an epoch

DTYPE = np.dtype([("epoch", "i4"), ("veh", "i4"), ("trip", "i4"),
                  ("run", "i2"), ("stop_i", "i2"), ("eta", "i4")])


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
        progress=None, model=None):
    model = model or PaceModel(net)
    tracks = {}
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
            _flush(model, res, tracks, closed, next_epoch, veh_idx, trip_idx,
                   emit=next_epoch - t_start >= warmup)
            next_epoch += epoch
            if progress and res.epochs % progress == 0:
                print(f"  t+{(next_epoch - t_start) / 60:5.0f} min  "
                      f"tracks {len(tracks):4d}  preds {res.buf.n}", flush=True)

        tr = tracks.get(veh)
        if tr is None:
            tr = tracks[veh] = track.Track(veh)
        done, passings = track.observe(tr, net, float(ts), lat, lon,
                                       speed, odo, trip)
        if done:
            base = model.shape_base[tr.shape_id]
            closed.extend((base + c.i, c) for c in done)
        if passings:
            vi = _idx(veh_idx, res.veh_ids, veh)
            ti = _idx(trip_idx, res.trip_ids, tr.trip)
            for i, t, gap in passings:
                k = (vi, ti, tr.run, i)
                if k not in res.truth:
                    res.truth[k] = t
                    res.gap[k] = gap

    if res is not None:
        _flush(model, res, tracks, closed, next_epoch, veh_idx, trip_idx, emit=True)
    con.close()
    return model, res


def _idx(m, names, key):
    i = m.get(key)
    if i is None:
        i = m[key] = len(names)
        names.append(key)
    return i


def _drain(model, tracks, closed, now):
    """Hand the epoch's cell crossings to the model.

    Finished crossings report whatever weight they have left. Crossings still
    in progress report the part that has elapsed, so a vehicle stuck in a jam
    informs the model while it is stuck rather than once it is through.
    """
    parts = [(gi, c, True) for gi, c in closed]
    parts += [(model.shape_base[t.shape_id] + t.cell.i, t.cell, False)
              for t in tracks.values() if t.cell is not None]
    closed.clear()
    if not parts:
        return

    idx = np.array([p[0] for p in parts])
    rows = [c.take(e, final) for (_, c, final), e
            in zip(parts, model.expected(idx))]
    keep = np.array([r is not None for r in rows])
    if not keep.any():
        return
    a = np.array([r for r in rows if r is not None], dtype=float)
    model.observe(idx[keep], a[:, 0], a[:, 1], a[:, 2], a[:, 3], now)


def _flush(model, res, tracks, closed, now, veh_idx, trip_idx, emit=True):
    _drain(model, tracks, closed, now)
    res.epochs += 1
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
        s_now = min(tr.s + tr.v * min(now - tr.ts, EXTRAP), tr.shape.length)
        dt = model.time_between(tr.shape_id, s_now, tr.sdist[i:])
        k = np.nonzero(dt <= HORIZON)[0]
        if not len(k):
            continue
        vi = _idx(veh_idx, res.veh_ids, veh)
        ti = _idx(trip_idx, res.trip_ids, tr.trip)
        res.pos.append((ep, vi, ti, tr.run, s_now))
        res.buf.extend(ep, vi, ti, tr.run, i + k,
                       np.rint(now - res.t0 + dt[k]).astype("i4"))
