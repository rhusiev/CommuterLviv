"""The hops a scan reads: every trip cut into stop-to-stop connections, and
the corridor of them a journey could ride."""
import math

import numpy as np


def _corridor(hops, transfers, egress, cap, starts, hi):
    """The hops a journey could ride: leaving a stop no sooner than it can be
    reached from the origin, and reaching one from which the door is still in
    reach by `hi`. Both are bounds - any number of rides, a change taking no
    time - so nothing a journey could ride is lost."""
    dep_s, arr_s, dep_t, arr_t, trip_of = hops
    near = {}

    def walked(v):
        if v not in near:
            near[v] = list(transfers.near(v, cap))
        return near[v]

    def reach(best, v, t, sign):
        """Puts `t` at `v` and on foot around it where it is later than what
        `best` holds - sooner, for a `sign` of -1."""
        if sign * (t - best.get(v, -sign * math.inf)) > 0:
            best[v] = t
            for w, x in walked(v):
                if sign * (t - sign * x - best.get(w, -sign * math.inf)) > 0:
                    best[w] = t - sign * x

    latest = {v: hi - e for v, e in egress.items() if e <= cap}
    useful = set()
    for u, v, d, a, t in zip(*hops):
        if t in useful or a <= latest.get(v, -math.inf):
            useful.add(t)
            reach(latest, u, d, 1)
    soonest = {}
    for u, d in starts:
        reach(soonest, u, d, -1)
    boarded = set()
    for u, v, d, a, t in zip(*map(reversed, hops)):
        if t in boarded or d >= soonest.get(u, math.inf):
            boarded.add(t)
            reach(soonest, v, a, -1)
    keep = [c for c, (u, v, d, a) in enumerate(zip(dep_s, arr_s, dep_t, arr_t))
            if soonest.get(u, math.inf) <= d and a <= latest.get(v, -math.inf)]
    return [[col[c] for c in keep] for col in hops]


def _connections(tt, live, trust, now, midnight, hi, quiet):
    """Every hop between consecutive stops leaving at `now` or later and
    arriving by `hi`, latest first, as lists of (from, to, departure, arrival,
    trip), with each trip's (route, vehicle, `LiveTrip.turns`) - the
    timetable's have no vehicle.
    Routes nothing has been seen on only with `quiet`. Ties keep a trip's
    later hop first, which a hop of no running time needs."""
    parts, trips = [], []
    for pat in tt.patterns:
        if not quiet and trust.get(pat.route) == "quiet":
            continue
        times = pat.times + midnight
        rows = np.flatnonzero((times[:, 0] <= hi) & (times[:, -1] >= now))
        if len(rows):
            parts.append(_hops(pat.stops, times[rows], len(trips)))
            trips += [(pat.route, None, math.inf)] * len(rows)
    for trip in live:
        parts.append(_hops(trip.stops, trip.times[None], len(trips)))
        trips.append((trip.route, trip.veh, trip.turns))
    if not parts:
        return ([],) * 5, trips
    cols = [np.concatenate(x) for x in zip(*parts)]
    keep = np.flatnonzero((cols[2] >= now) & (cols[3] <= hi))
    order = keep[np.lexsort((-keep, -cols[2][keep]))]
    return [x[order].tolist() for x in cols], trips


def _hops(stops, times, first):
    n = len(times)
    return (np.tile(stops[:-1], n), np.tile(stops[1:], n),
            times[:, :-1].ravel(), times[:, 1:].ravel(),
            np.repeat(np.arange(first, first + n), len(stops) - 1))
