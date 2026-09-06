"""The four predictors, reduced to one common form.

Whatever a predictor is inside, what comes out here is the same three columns:
which crossing it was predicting, at which epoch it said so, and how wrong it
turned out to be. Once they all speak that language they can be compared on
exactly the events and epochs they all answered - see score.py.

  ours      the pace model in model.py, replayed causally
  api       trip_updates, replayed from the recorded change log
  lad       the arrivals board at api.lad.lviv.ua that the public is shown
  schedule  the static timetable, with no real-time input at all, as a floor
"""
import os
import sqlite3

import numpy as np

from . import gtfs

DB = os.path.join(gtfs.DATA, "feed.db")
EPOCH = 60.0
MAX_HORIZON = 45 * 60.0
LAD_STALE = 120.0   # two poll periods; see _from_log


class Series:
    """What one predictor said, flattened: event, epoch, horizon, error."""

    __slots__ = ("event", "epoch", "horizon", "error")

    def __init__(self, parts):
        cols = [np.concatenate([p[i] for p in parts]) if parts else np.zeros(0)
                for i in range(4)]
        self.event, self.epoch, self.horizon, self.error = cols
        self.event = self.event.astype(np.int64)

    def __len__(self):
        return len(self.event)

    def select(self, mask):
        out = object.__new__(Series)
        for f in Series.__slots__:
            setattr(out, f, getattr(self, f)[mask])
        return out


def ours(res, truth):
    """Our own predictions, which name a crossing in full and never ambiguously."""
    a = res.buf.done()
    cols = np.stack([a[f] for f in ("veh", "trip", "run", "stop_i")], axis=1)
    uniq, inv = np.unique(cols.astype(np.int64), axis=0, return_inverse=True)
    ev = np.array([truth.event.get(tuple(map(int, k)), -1) for k in uniq],
                  dtype=np.int64)[inv.ravel()]

    ok = ev >= 0
    ev, at, eta = ev[ok], a["epoch"][ok] + res.t0, a["eta"][ok] + res.t0
    t = truth.time[ev]
    m = at < t
    return Series([(ev[m], at[m], (t - at)[m], (eta - t)[m])])


def api(res, truth, db=DB, epoch=EPOCH):
    """Replay the recorded trip_updates change log at our own epochs."""
    trip_no = {t: i for i, t in enumerate(res.trip_ids)}
    stop_no = {}
    for trip, i in trip_no.items():
        for si, s in enumerate(res.net.trip_stops[trip][0]):
            stop_no.setdefault((i, s), si)

    log = {}
    for trip, stop, poll_ts, t in _rows(db, "SELECT trip_id, stop_id, poll_ts, t "
                                            "FROM pred ORDER BY poll_ts"):
        i = trip_no.get(trip)
        si = stop_no.get((i, stop))
        if si is None:
            continue
        e = truth.by_trip_stop.at((i, si), poll_ts)
        if e is not None:
            log.setdefault(e, ([], []))[0].append(poll_ts)
            log[e][1].append(t)
    return _from_log(log, truth, epoch)


def lad(res, net, truth, db=DB, epoch=EPOCH, stale=LAD_STALE):
    """The arrivals board, keyed by vehicle and stop because that is all it says.

    It never says which pass, so what it was talking about is taken to be the
    next crossing after the poll - it is a next-arrival board. Only the stops
    the collector polls appear, so this predictor is scored on a much smaller
    slice of the network than the other three.
    """
    veh_no = {v: i for i, v in enumerate(res.veh_ids)}
    by_code = {}
    for sid, s in net.stops.items():
        code = (s.get("code") or "").strip().lstrip("0")
        if code.isdigit():
            by_code.setdefault(code, sid)

    log = {}
    for veh, code, poll_ts, arr in _rows(db, "SELECT veh_id, stop_code, poll_ts, arr "
                                             "FROM lad WHERE veh_id IS NOT NULL "
                                             "ORDER BY poll_ts"):
        stop = by_code.get(str(code).lstrip("0"))
        e = truth.by_veh_stop.at((veh_no.get(veh), stop), poll_ts)
        if e is not None:
            log.setdefault(e, ([], []))[0].append(poll_ts)
            log[e][1].append(arr)
    return _from_log(log, truth, epoch, stale)


def schedule(res, truth, net, epoch=EPOCH):
    """The timetable alone. Always available, never updated."""
    import datetime
    from .model import TZ

    parts = []
    for (ti, si), e in truth.by_trip_stop:
        info = net.trip_stops.get(res.trip_ids[ti])
        if info is None:
            continue
        t = truth.time[e]
        midnight = datetime.datetime.fromtimestamp(t, TZ).replace(
            hour=0, minute=0, second=0, microsecond=0).timestamp()
        at = np.arange(np.ceil((t - MAX_HORIZON) / epoch) * epoch, t, epoch)
        parts.append((np.full(len(at), e), at, t - at,
                      np.full(len(at), midnight + info[2][si] - t)))
    return Series(parts)


def _rows(db, sql):
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    try:
        return con.execute(sql).fetchall()
    finally:
        con.close()


def _from_log(log, truth, epoch, stale=None):
    """Score a recorded prediction log at our own epochs.

    What a feed was predicting at an epoch is whatever it last said before it.
    How long that last word stands depends on the feed. `trip_updates` is
    recorded as a change log, so a value stands until it is replaced and there
    is no bound. The arrivals board is recorded as a snapshot of what it
    displayed, so a vehicle missing from the next poll is a board that has
    stopped answering, not one repeating itself: `stale` says how long a value
    survives without being republished.

    Epochs earlier than `MAX_HORIZON` before the crossing are dropped, because
    that is as far ahead as our own replay predicts and the four have to be
    asked the same questions.
    """
    parts = []
    for e, (polls, values) in log.items():
        t = truth.time[e]
        polls = np.asarray(polls, dtype=float)
        start = max(polls[0], t - MAX_HORIZON)
        at = np.arange(np.ceil(start / epoch) * epoch, t, epoch)
        if not len(at):
            continue
        last = np.searchsorted(polls, at, "right") - 1
        if stale is not None:
            fresh = at - polls[last] <= stale
            at, last = at[fresh], last[fresh]
            if not len(at):
                continue
        parts.append((np.full(len(at), e), at, t - at,
                      np.asarray(values, dtype=float)[last] - t))
    return Series(parts)
