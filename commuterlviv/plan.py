"""Door to door: how to get from one point of the city to another.

The question is not "when is the next 3A" but "I am here, I want to be there,
what do I do". The answer is a small ranked list of journeys, each a chain of
legs: walk to a stop, ride, maybe walk to another stop and ride again, walk to
the door.

Three things make that answer honest, and each is a decision worth keeping:

Walking is measured on pavement, not as the crow flies - `walk.py` holds the
footpath graph, and this module only ever asks it for seconds.

No radius is hardcoded for "which stops are close enough". The bound is the
journey's own alternative: walking the whole way. A walk to a stop that takes
longer than walking to the destination can never be part of a better journey,
so that time is the limit, and in a short hop across a square it is a minute
while across the city it is an hour. The pure walk is also offered as an
option, so the comparison is one the rider can see.

A tracked vehicle is a trip. The search does not consult the live predictions
as a correction applied afterwards; each vehicle the model is tracking enters
the timetable as an extra trip, whose stop times are exactly what the arrivals
board would show. So a leg is "live" when the search chose one of those, and
"scheduled" when it chose a timetable trip - which is what happens past the
model's 45-minute horizon, where there are no live trips at all, and for any
route nothing is tracked on. Every leg says which it was.

The search is RAPTOR (Delling, Pajor and Werneck, 2012): round k holds the
earliest arrival reachable with k rides, each round scans every route touching
a stop improved in the previous round, and between rounds a walk from every
improved stop relaxes the neighbours on foot. Rounds are few - three rides is
already more changes than anyone wants - so it finishes in milliseconds
without a single heap of trips.
"""
import datetime
import math
import pickle
import zoneinfo
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from . import network, replay, walk as footpaths

DATA = Path(__file__).resolve().parent.parent / "data"
TRANSFERS = DATA / "transfers.npz"

TZ = zoneinfo.ZoneInfo("Europe/Kyiv")
DAY = 86400.0

# The longest stop-to-stop walk kept in the transfer table. Not a limit on the
# search - the search's own limit is the pure walk, below - but on the size of
# the cached table, which is quadratic in this number
TRANSFER_CAP = 900.0

# Changing vehicles costs more than the walk: a rider will not sprint for a
# door, and a plan that assumes they will is a plan that strands them
CHANGE = 60.0

# Rides per journey. Three is already two changes, and the fourth round costs
# as much as the first three together while nobody would ride it
ROUNDS = 3


@dataclass(frozen=True, slots=True)
class Leg:
    """One unbroken movement. `route` and `veh` are None on a walk."""
    kind: str                # "walk" or "ride"
    dep: float               # unix seconds
    arr: float
    a: int                   # stop index, or -1 for the origin/destination
    b: int
    route: str | None = None
    veh: int | None = None
    live: bool = False


@dataclass(frozen=True, slots=True)
class Journey:
    legs: tuple[Leg, ...]

    @property
    def dep(self):
        return self.legs[0].dep

    @property
    def arr(self):
        return self.legs[-1].arr

    @property
    def rides(self):
        return sum(1 for leg in self.legs if leg.kind == "ride")

    @property
    def live(self):
        """True when every ride in it is a vehicle the model can see."""
        rides = [leg for leg in self.legs if leg.kind == "ride"]
        return bool(rides) and all(leg.live for leg in rides)


class Pattern:
    """Every trip that calls at the same stops in the same order.

    `times` is one row per trip and one column per stop, in seconds since the
    service day's midnight, with rows sorted by departure - so "the first trip
    leaving stop k after t" is a binary search down a column.
    """

    __slots__ = ("route", "stops", "times")

    def __init__(self, route, stops, times):
        self.route = route
        self.stops = np.asarray(stops, dtype=np.int32)
        self.times = np.asarray(times, dtype=np.float64)

    def after(self, k, when):
        """(row, shift) of the first trip leaving stop k at or after `when`,
        in seconds since midnight, or None if there is no such trip.

        `shift` is a whole day when the trip found is tomorrow's: a GTFS day
        runs past 24:00, so a query at 23:50 also has to look at tomorrow's
        early trips, which is the same search a day back. Every other time on
        that trip is then a day later too, and the caller adds `shift` to it.
        """
        col = self.times[:, k]
        i = int(np.searchsorted(col, when, side="left"))
        if i < len(col):
            return i, 0.0
        i = int(np.searchsorted(col, when - DAY, side="left"))
        if i < len(col):
            return i, DAY
        return None


class LiveTrip:
    """One tracked vehicle, dressed as a pattern with a single trip.

    Its times are absolute unix seconds rather than seconds since midnight,
    because a prediction is about this afternoon and not about a service day.
    """

    __slots__ = ("route", "veh", "stops", "times")

    def __init__(self, route, veh, stops, times):
        self.route = route
        self.veh = veh
        self.stops = np.asarray(stops, dtype=np.int32)
        self.times = np.asarray(times, dtype=np.float64)


class Timetable:
    """The scheduled city, in the shape RAPTOR reads it.

    Stops are indexed by this table's own order - `sorted(net.stops)` - and
    `stop_i` translates a feed id into that index. The live side hands over
    predictions keyed by the catalog's stop order instead, so the caller
    supplies a translation rather than either side assuming the other's.
    """

    def __init__(self, net):
        self.net = net
        self.stops = sorted(net.stops)
        self.stop_i = {s: i for i, s in enumerate(self.stops)}
        by_key = {}
        for trip, (stops, _, sched) in net.trip_stops.items():
            route = net.trip_route.get(trip)
            if route is None or len(stops) < 2:
                continue
            key = (route, tuple(stops))
            by_key.setdefault(key, []).append(sched)
        self.patterns = []
        for (route, stops), rows in by_key.items():
            times = np.array(rows, dtype=np.float64)
            times = times[np.argsort(times[:, 0], kind="stable")]
            idx = [self.stop_i[s] for s in stops]
            self.patterns.append(Pattern(route, idx, times))
        self.at_stop = [[] for _ in self.stops]
        for p, pat in enumerate(self.patterns):
            for k, s in enumerate(pat.stops):
                self.at_stop[s].append((p, k))

    @property
    def lat(self):
        return np.array([self.net.stops[s]["lat"] for s in self.stops])

    @property
    def lon(self):
        return np.array([self.net.stops[s]["lon"] for s in self.stops])


def _seconds_since_midnight(now):
    local = datetime.datetime.fromtimestamp(now, TZ)
    midnight = local.replace(hour=0, minute=0, second=0, microsecond=0)
    return now - midnight.timestamp(), midnight.timestamp()


def stop_nodes(tt, walk):
    """The graph node each stop stands on, or -1 where there is no pavement
    within 150 m. Every Lviv stop has some, but a feed can always gain one in a
    field, and a planner that snapped it to a road a kilometre away would
    quietly invent a walk nobody can take."""
    lat, lon = tt.lat, tt.lon
    out = np.full(len(tt.stops), -1, dtype=np.int64)
    for i in range(len(out)):
        near = walk.near(float(lat[i]), float(lon[i]))
        if near:
            out[i] = near[0][1]
    return out


def build_transfers(tt, walk, cap=TRANSFER_CAP, path=TRANSFERS):
    """Stop-to-stop walking seconds, as a compressed sparse row table.

    One Dijkstra per stop, capped at `cap`, which over a thousand stops is a
    few seconds - once, offline, into `data/transfers.npz`. At query time this
    is read and cut down to whatever the journey's own walking bound is.
    """
    node = stop_nodes(tt, walk)
    at_node = {}
    for i, n in enumerate(node):
        if n >= 0:
            at_node.setdefault(int(n), []).append(i)
    start = [0]
    to, cost = [], []
    for i in range(len(node)):
        if node[i] < 0:
            start.append(len(to))
            continue
        seen = walk.reach([(int(node[i]), 0.0)], cap)
        for n, t in seen.items():
            for j in at_node.get(n, ()):
                if j != i:
                    to.append(j)
                    cost.append(t)
        start.append(len(to))
    path.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(path, node=node,
                        to=np.array(to, dtype=np.int32),
                        cost=np.array(cost, dtype=np.float32),
                        start=np.array(start, dtype=np.int64))
    return path


class Transfers:
    __slots__ = ("node", "to", "cost", "start")

    def __init__(self, node, to, cost, start):
        self.node, self.to, self.cost, self.start = node, to, cost, start

    @classmethod
    def load(cls, path=TRANSFERS):
        if not path.exists():
            raise FileNotFoundError(
                f"{path} is not there - run `python -m commuterlviv plan "
                "--build` once to walk between every pair of stops")
        with np.load(path) as z:
            return cls(z["node"], z["to"], z["cost"], z["start"])

    def near(self, i, limit):
        lo, hi = self.start[i], self.start[i + 1]
        for k in range(lo, hi):
            t = float(self.cost[k])
            if t <= limit:
                yield int(self.to[k]), t


def live_trips(tt, arrivals, catalog, now, horizon=replay.HORIZON):
    """Every tracked vehicle as a one-trip pattern, and the (stop, route)
    pairs they cover - the caller uses those to suppress the scheduled
    departures the predictions have already superseded."""
    trips, covered = [], set()
    if arrivals is None or not len(arrivals.eta):
        return trips, covered
    for veh in np.unique(arrivals.eta["veh"]):
        rows = arrivals.of(int(veh))
        stops, times = [], []
        for r in rows:
            when = float(r["t"])
            if when < now or when > now + horizon:
                continue
            sid = catalog.stops[int(r["stop"])]
            i = tt.stop_i.get(sid)
            if i is None:
                continue
            stops.append(i)
            times.append(when)
            covered.add((i, catalog.routes[int(r["route"])]))
        if len(stops) >= 2:
            route = catalog.routes[int(rows[0]["route"])]
            trips.append(LiveTrip(route, int(veh), stops, times))
    return trips, covered


def _reach(walk, lat, lon, limit):
    """Walking seconds from a point to every node within `limit`."""
    sources = [(i, d / footpaths.SPEED)
               for d, i in walk.near(lat, lon, within=150.0)]
    if not sources:
        return {}
    return walk.reach(sources, limit)


def _at_stops(seen, node, limit):
    """A node-keyed reach, read at the stops standing on those nodes."""
    out = {}
    for i, n in enumerate(node):
        if n < 0:
            continue
        t = seen.get(int(n))
        if t is not None and t <= limit:
            out[i] = t
    return out


def journeys(tt, walk, transfers, origin, dest, now, arrivals=None,
             catalog=None, rounds=ROUNDS, keep=5):
    """Ranked journeys from `origin` to `dest` leaving at `now`.

    `origin` and `dest` are (lat, lon). Soonest arrival first; a slower journey
    is only kept when it has fewer changes than every faster one, because a
    rider offered five ways to arrive within a minute of each other wants the
    simple one.
    """
    walked = _walk_through(walk, origin, dest)
    limit = walked if walked is not None else TRANSFER_CAP
    access = _at_stops(_reach(walk, *origin, limit), transfers.node, limit)
    egress = _at_stops(_reach(walk, *dest, limit), transfers.node, limit)
    if not access or not egress:
        return _only_walking(walked, now)

    live, covered = ([], set()) if arrivals is None else \
        live_trips(tt, arrivals, catalog, now)
    at_stop_live = [[] for _ in tt.stops]
    for p, trip in enumerate(live):
        for k, s in enumerate(trip.stops):
            at_stop_live[s].append((p, k))

    sod, midnight = _seconds_since_midnight(now)
    best = {}                      # stop -> earliest arrival, any round
    board = {}                     # (round, stop) -> the leg that got there
    round_best = [dict() for _ in range(rounds + 1)]
    for i, t in access.items():
        best[i] = round_best[0][i] = now + t
        board[(0, i)] = Leg("walk", now, now + t, -1, i)
    touched = set(access)

    for k in range(1, rounds + 1):
        marked = set()
        for (kind, p), first in _routes_touching(tt, at_stop_live, touched):
            pat = live[p] if kind == "live" else tt.patterns[p]
            _scan(pat, kind == "live", first, k, sod, midnight, now, covered,
                  round_best, best, board, marked)
        for i in list(marked):
            here = round_best[k][i]
            for j, t in transfers.near(i, min(limit, TRANSFER_CAP)):
                arrive = here + t
                if arrive < min(best.get(j, math.inf),
                                round_best[k].get(j, math.inf)):
                    round_best[k][j] = best[j] = arrive
                    board[(k, j)] = Leg("walk", here, arrive, i, j)
                    marked.add(j)
        if not marked:
            break
        touched = marked

    found = []
    for k in range(1, rounds + 1):
        arrive, tail = None, None
        for i, t in egress.items():
            got = round_best[k].get(i)
            if got is not None and (arrive is None or got + t < arrive):
                arrive, tail = got + t, Leg("walk", got, got + t, i, -1)
        if arrive is not None:
            legs = _unwind(board, k, tail.a) + [tail]
            found.append(Journey(tuple(legs)))
    found.extend(_only_walking(walked, now))
    return _rank(found, keep)


def _routes_touching(tt, at_stop_live, stops):
    """Every route calling at one of these stops, each named once, paired with
    the earliest position it is reached at - which is where a scan may board.
    A route is ("sched", pattern index) or ("live", vehicle trip index)."""
    first = {}
    for s in stops:
        for p, k in tt.at_stop[s]:
            key = ("sched", p)
            if k < first.get(key, math.inf):
                first[key] = k
        for p, k in at_stop_live[s]:
            key = ("live", p)
            if k < first.get(key, math.inf):
                first[key] = k
    return first.items()


def _scan(pat, is_live, first, k, sod, midnight, now, covered,
          round_best, best, board, marked):
    """One route, ridden from the earliest stop it can be boarded at.

    Walks the stop list once. While not aboard this is the search for the first
    departure; once aboard every stop is a chance to improve an arrival, and a
    stop reachable earlier than the vehicle gets there is a chance to catch an
    earlier trip on the same route - which is the whole of RAPTOR.

    A live trip's times are already absolute. A scheduled one's are seconds
    since the service midnight, and a trip boarded just before midnight for a
    departure after it carries `shift` - a whole day - so that its later stops
    do not come out a day before the boarding.
    """
    trip = dep_at = start = shift = None
    for i in range(first, len(pat.stops)):
        s = int(pat.stops[i])
        if trip is not None:
            arrive = (float(pat.times[i]) if is_live
                      else midnight + shift + float(pat.times[trip, i]))
            if arrive < min(best.get(s, math.inf),
                            round_best[k].get(s, math.inf)):
                round_best[k][s] = best[s] = arrive
                board[(k, s)] = Leg("ride", dep_at, arrive, start, s,
                                    pat.route, getattr(pat, "veh", None),
                                    is_live)
                marked.add(s)
        ready = round_best[k - 1].get(s)
        if ready is None:
            continue
        ready += CHANGE if k > 1 else 0.0
        if is_live:
            when = float(pat.times[i])
            if trip is None and when >= ready:
                trip, dep_at, start, shift = 0, when, s, 0.0
            continue
        if (s, pat.route) in covered:
            continue
        got = pat.after(i, sod + (ready - now))
        if got is None:
            continue
        row, jump = got
        when = midnight + jump + float(pat.times[row, i])
        if trip is None or when < dep_at:
            trip, dep_at, start, shift = row, when, s, jump


def _unwind(board, k, stop):
    legs = []
    while k >= 0:
        leg = board.get((k, stop))
        if leg is None:
            break
        legs.append(leg)
        stop = leg.a
        if leg.kind == "ride":
            k -= 1
        if stop == -1:
            break
    legs.reverse()
    return legs


def _walk_through(walk, origin, dest, ceiling=4 * 3600.0):
    """Seconds to walk the whole way, or None if the two ends are not
    connected on foot within `ceiling`. This is the bound on every other walk
    in the plan.

    Searched at a guess and doubled until it lands, because an uncapped
    Dijkstra walks the whole city - a second - to answer a question about two
    points a kilometre apart. The guess is the straight line, which the streets
    can only be longer than.
    """
    goal = walk.near(*dest)
    sources = [(i, d / footpaths.SPEED) for d, i in walk.near(*origin)]
    if not goal or not sources:
        return None
    want = {i: d / footpaths.SPEED for d, i in goal}
    crow = footpaths.metres(*origin, *dest) / footpaths.SPEED
    limit = max(crow * 1.3, 300.0)
    while True:
        seen = walk.reach(sources, limit)
        best = [t + want[i] for i, t in seen.items() if i in want]
        if best:
            return min(best)
        if limit >= ceiling:
            return None
        limit = min(limit * 2, ceiling)


def _only_walking(walked, now):
    if walked is None:
        return []
    return [Journey((Leg("walk", now, now + walked, -1, -1),))]


def _rank(found, keep):
    """Soonest first, and drop a journey no rider would pick: one that arrives
    later than another and changes at least as often."""
    found.sort(key=lambda j: (j.arr, j.rides))
    out = []
    for j in found:
        if any(o.arr <= j.arr and o.rides <= j.rides for o in out):
            continue
        out.append(j)
    return out[:keep]


def load(net=None):
    """The three pieces a search needs. The timetable is built here - a couple
    of seconds - and cached, because it is the only one small enough to."""
    net = net or network.load()
    cache = DATA / "timetable.pkl"
    if cache.exists() and cache.stat().st_mtime >= Path(network.CACHE).stat().st_mtime:
        with open(cache, "rb") as fh:
            tt = pickle.load(fh)
    else:
        tt = Timetable(net)
        with open(cache, "wb") as fh:
            pickle.dump(tt, fh, protocol=5)
    return tt, footpaths.load(), Transfers.load()


def main(argv):
    """`python -m commuterlviv plan --build` once, then
    `python -m commuterlviv plan LAT,LON LAT,LON` to try one."""
    net = network.load()
    if "--build" in argv:
        tt = Timetable(net)
        print(f"{len(tt.patterns)} patterns over {len(tt.stops)} stops")
        print("walking between every pair of stops")
        print(build_transfers(tt, footpaths.load()))
        return
    if len(argv) < 2:
        print("usage: plan LAT,LON LAT,LON  |  plan --build")
        return
    import time
    origin, dest = [tuple(float(x) for x in a.split(",")) for a in argv[:2]]
    tt, walk, transfers = load(net)
    now = time.time()
    began = time.perf_counter()
    out = journeys(tt, walk, transfers, origin, dest, now)
    print(f"{len(out)} options in {1e3 * (time.perf_counter() - began):.0f} ms")
    for j in out:
        print(f"\n{_clock(j.dep)} -> {_clock(j.arr)}  "
              f"{(j.arr - j.dep) / 60:.0f} min, {j.rides} rides")
        for leg in j.legs:
            where = ("the door" if leg.b < 0
                     else net.stops[tt.stops[leg.b]]["name"])
            if leg.kind == "walk":
                print(f"  walk {(leg.arr - leg.dep) / 60:.0f} min to {where}")
            else:
                short = net.routes[leg.route]["short"]
                tag = "live" if leg.live else "timetable"
                print(f"  {_clock(leg.dep)} {short} to {where} "
                      f"({_clock(leg.arr)}, {tag})")


def _clock(t):
    return datetime.datetime.fromtimestamp(t, TZ).strftime("%H:%M")


if __name__ == "__main__":  # pragma: no cover - the CLI entry does this
    import sys
    main(sys.argv[1:])
