"""A search from a point, or from aboard a vehicle, to the door."""
import dataclasses
import math

import numpy as np

from .. import walk as footpaths
from .hops import _connections, _corridor
from .journey import Aboard, Journey, Leg
from .ranking import _listed, _rank
from .scan import BACKUP_WINDOW, _Profile, _quickest, change_slack
from .timetable import _seconds_since_midnight
from .tracked import live_trips, route_confidence
from .transfers import TRANSFER_CAP, _at_stops, _reach


ROUNDS = 3      # rides per journey; a fourth round costs as much as the first three

# Each walk also capped to this many seconds, in slots of the scan of their
# own: the earliest arrival alone loses a ride from the door to a slightly
# faster one behind a long walk. Both caps here are at `walk.SPEED`; a search
# paced slower or faster keeps the distances and scales the seconds
WALK_CAPS = (600.0, 300.0)

LONGEST_WALK = 4 * 3600.0   # s past which the ends count as not joined on foot
# s: the first bound on walking the whole way is the straight line's time
# times DETOUR, but never under FIRST_WALK
DETOUR = 1.3
FIRST_WALK = 300.0


def journeys(tt, walk, transfers, origin, dest, now, arrivals=None,
             catalog=None, rounds=ROUNDS, keep=8, assess=True, hurry=1.0):
    """Ranked journeys from `origin` to `dest` (both (lat, lon)) leaving at
    `now`, which may be in the future: the vehicles being tracked are still
    used, for as far ahead as their predictions reach.

    `assess` off leaves every scheduled route believed. Silence only means a
    route is not running when the departure is close enough that the vehicles
    on the road now are the ones that would carry it.

    Somebody slower or faster on foot than `walk.SPEED` is searched for with
    `walk` and `transfers` paced to them. `hurry` is the share of that walk's
    time the walk to the first stop takes when they hurry, 1 for not at all;
    the departures only hurrying catches are options of their own
    (`_Profile.hurrying`).

    An `Aboard` origin is searched as getting off at the vehicle's next stop
    when it gets there, with the stops in reach of that one, and each journey
    found is then ridden there on it (`_on`). One the planner no longer sees
    running gets none.
    """
    sod, midnight = _seconds_since_midnight(now)
    tt = tt.on(midnight)
    live, covered = ([], {}) if arrivals is None else \
        live_trips(tt, arrivals, catalog, now)
    if isinstance(origin, Aboard):
        trip = next((x for x in live if x.veh == origin.veh), None)
        if trip is None:
            return []
        u, start = int(trip.stops[0]), float(trip.times[0])
        walked, *_ = _walk_through(walk, (float(tt.lat[u]), float(tt.lon[u])),
                                  dest)
    else:
        trip, start = None, now
        walked, seen, here = _walk_through(walk, origin, dest)
    limit = walked if walked is not None else TRANSFER_CAP * walk.pace
    if trip is None:
        access = _at_stops(seen, transfers.stands, limit, here)
    else:
        # bounded as a search from that stop is, then the ride there added
        access = {**dict(transfers.near(u, limit)), u: 0.0}
        walked = None if walked is None else walked + start - now
    there = walk.attach(*dest)
    egress = _at_stops(_reach(walk, there, limit), transfers.stands, limit, there)
    if not access or not egress:
        return [] if trip else _only_walking(walked, now)

    trust = (route_confidence(tt, live, sod)
             if assess and arrivals is not None else {})
    paced = [c * walk.pace for c in WALK_CAPS]
    caps = (limit, *(c for c in paced if c < limit))
    hi = now + (walked if walked is not None else LONGEST_WALK) + BACKUP_WINDOW
    soonest = access if trip else _quickest(access, hurry)
    for quiet in (False, True):
        hops, trips = _connections(tt, live, trust, now, midnight, hi, quiet)
        hops = _corridor(hops, transfers, egress, caps[0],
                         [(u, start + t) for u, t in soonest.items()], hi)
        scan = _Profile(hops, trips, trust, transfers, egress, caps, rounds,
                        covered, now)
        found = scan.options(access, start)
        more = scan.near(access, start, found)
        if trip is None:
            more += scan.hurrying(access, hurry, start, found)
        found = scan.backed(found + more)
        if trip is None:
            found += _only_walking(walked, now)
        else:
            found = _on(tt, trip, found + _off_first(trip, egress), now)
        # a ride slower than walking is still worth it when already on it
        found = _rank(found, keep, walked if trip is None else None)
        if quiet or any(j.rides for j in found) or \
                "quiet" not in trust.values():
            return _listed(found)


def _walk_through(walk, origin, dest, ceiling=LONGEST_WALK):
    """Seconds to walk the whole way, or None if the ends are not connected on
    foot within `ceiling`. This bounds every other walk in the plan. Also the
    walk from `origin` to every node, whole up to that bound, or to `ceiling`,
    and where `origin` steps onto the footpaths.

    The limit starts at the straight-line time, which the streets can only be
    longer than, and doubles until the search lands; an uncapped Dijkstra would
    walk the whole city.
    """
    start, goal = walk.attach(*origin), walk.attach(*dest)
    ends = goal.ends() if goal else []
    direct = start.along(goal) if start and goal else math.inf
    limit = max(walk.flat(footpaths.metres(*origin, *dest)) * DETOUR, FIRST_WALK)
    while True:
        seen = _reach(walk, start, limit)
        # a plain float: as an np.float64 this cap makes the profile scan
        # half again slower
        walked = min([direct, *(float(seen[i]) + t for i, t in ends)])
        if walked <= limit:
            return walked, seen, start
        if limit >= ceiling:
            return None, seen, start
        limit = min(limit * 2, ceiling)


def _off_first(trip, egress):
    """Getting off at the vehicle's next stop and walking from there, as a
    journey found from that stop: `_on` rides it there."""
    u, t = int(trip.stops[0]), float(trip.times[0])
    if u not in egress:
        return []
    return [Journey((Leg("walk", t, t, -1, u),
                     Leg("walk", t, t + egress[u], u, -1)))]


def _on(tt, trip, found, now):
    """Journeys found from getting off `trip` at its next stop, each starting
    with the walk from there, as ridden there on `trip` from `now` instead. A
    first ride on `trip` itself is staying on, so the two are one ride; any
    other is a change, and one boarded too soon for it is dropped. Riding needs
    the stop before to start from; a vehicle standing at its first stop has
    none, and its journeys start at that stop."""
    u, at = int(trip.stops[0]), float(trip.times[0])
    before = _before(tt, trip)
    out = []
    for j in found:
        first, rest = j.legs[0], j.legs[1:]
        backs = j.backups[1:]
        if first.b != u:
            rest, backs = (Leg("walk", at, first.arr, u, first.b), *rest), \
                ((), *backs)
        on = None if before is None else Leg(
            "ride", now, at, before, u, trip.route, trip.veh, True,
            "terminus" if at >= trip.turns else "live")
        if rest and rest[0].kind == "ride" and rest[0].veh == trip.veh:
            on = dataclasses.replace(rest[0], dep=now,
                                     a=rest[0].a if before is None else before)
            rest, backs = rest[1:], backs[1:]
        elif _rushed(rest, at, now):
            continue
        legs = rest if on is None else (on, *rest)
        if not legs:
            continue
        # nobody on board needs another way to get on it
        backs = backs if on is None else ((), *backs)
        out.append(Journey(legs, backs if j.backups else (), on is not None))
    return out


def _rushed(legs, at, now):
    """Whether the first ride of `legs`, after getting off at `at`, leaves
    sooner than a change allows."""
    k = next((i for i, leg in enumerate(legs) if leg.kind == "ride"), None)
    if k is None:
        return False
    ready = legs[k - 1].arr if k else at
    return legs[k].dep < ready + change_slack(ready - now)


def _before(tt, trip):
    """The stop `trip` called at before its next one, from a pattern of its
    route running the same two stops after it next, or None."""
    if len(trip.stops) < 2:
        return None
    u, v = trip.stops[0], trip.stops[1]
    for pat in tt.by_route.get(trip.route, ()):
        hit = np.flatnonzero((pat.stops[1:-1] == u) & (pat.stops[2:] == v))
        if len(hit):
            return int(pat.stops[hit[0]])
    return None


def _only_walking(walked, now):
    if walked is None:
        return []
    return [Journey((Leg("walk", now, now + walked, -1, -1),))]
