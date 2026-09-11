"""Door to door: ranked journeys of walk, ride, walk between two points.

Walking is measured on the footpath graph in `walk.py`, never as the crow flies.
Nothing bounds "close enough" by a radius: the bound is the time it would take to
walk the whole way, which is also offered as an option.

Each tracked vehicle enters the timetable as an extra trip whose stop times are
the live predictions, so a leg is "live" when the search picked one of those and
"scheduled" otherwise.

The search is RAPTOR (Delling, Pajor and Werneck, 2012): round k holds the
earliest arrival reachable with k rides, each round scans every route touching a
stop improved in the previous round, and between rounds a walk from every
improved stop relaxes its neighbours on foot.
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

# longest stop-to-stop walk kept in the cached transfer table, whose size is
# quadratic in it; the search's own limit is the pure walk
TRANSFER_CAP = 900.0

CHANGE = 60.0   # s of slack per change, over and above the walk

ROUNDS = 3      # rides per journey; a fourth round costs as much as the first three


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

    `times` is one row per trip, one column per stop, in seconds since the
    service day's midnight, rows sorted by departure so `after` is a bisect.
    """

    __slots__ = ("route", "stops", "times")

    def __init__(self, route, stops, times):
        self.route = route
        self.stops = np.asarray(stops, dtype=np.int32)
        self.times = np.asarray(times, dtype=np.float64)

    def after(self, k, when):
        """(row, shift) of the first trip leaving stop k at or after `when`,
        in seconds since midnight, or None.

        `shift` is DAY when the trip found is tomorrow's; the caller adds it to
        every other time on that trip.
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
    """One tracked vehicle dressed as a single-trip pattern; its times are
    absolute unix seconds, not seconds since midnight."""

    __slots__ = ("route", "veh", "stops", "times")

    def __init__(self, route, veh, stops, times):
        self.route = route
        self.veh = veh
        self.stops = np.asarray(stops, dtype=np.int32)
        self.times = np.asarray(times, dtype=np.float64)


class Timetable:
    """The scheduled city, in the shape RAPTOR reads it.

    Stops are indexed by `sorted(net.stops)` and `stop_i` maps a feed id into
    that; the live side keys by the catalog's order instead, so callers must
    translate.
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
    """The graph node each stop stands on, or -1 with no pavement within 150 m."""
    lat, lon = tt.lat, tt.lon
    out = np.full(len(tt.stops), -1, dtype=np.int64)
    for i in range(len(out)):
        near = walk.near(float(lat[i]), float(lon[i]))
        if near:
            out[i] = near[0][1]
    return out


def build_transfers(tt, walk, cap=TRANSFER_CAP, path=TRANSFERS):
    """Stop-to-stop walking seconds as a CSR table: one Dijkstra per stop,
    capped at `cap`, written offline to `data/transfers.npz`."""
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
    """Every tracked vehicle as a one-trip pattern, plus the (stop, route) pairs
    they cover, whose scheduled departures the caller should suppress."""
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
    """Ranked journeys from `origin` to `dest` (both (lat, lon)) leaving at
    `now`: soonest arrival first, keeping a slower one only if it changes less."""
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
    the earliest position a scan may board at.

    A route is ("sched", pattern index) or ("live", vehicle trip index).
    """
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

    A scheduled trip's times are seconds since the service midnight, so one
    boarded before midnight for a departure after it carries `shift` = DAY; a
    live trip's times are already absolute.
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
    """Seconds to walk the whole way, or None if the ends are not connected on
    foot within `ceiling`. This bounds every other walk in the plan.

    The limit starts at the straight-line time, which the streets can only be
    longer than, and doubles until the search lands; an uncapped Dijkstra would
    walk the whole city.
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
    """Soonest first, dropping any journey another one dominates."""
    found.sort(key=lambda j: (j.arr, j.rides))
    out = []
    for j in found:
        if any(o.arr <= j.arr and o.rides <= j.rides for o in out):
            continue
        out.append(j)
    return out[:keep]


def load(net=None):
    """The three pieces a search needs; the timetable is built and cached here."""
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
