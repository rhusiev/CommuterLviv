"""Door to door: ranked journeys of walk, ride, walk between two points.

Walking is measured on the footpath graph in `walk.py`, never as the crow flies.
Nothing bounds "close enough" by a radius: the bound is the time it would take to
walk the whole way, which is also offered as an option.

Each tracked vehicle enters the timetable as an extra trip whose stop times are
the live predictions, so a leg is "live" when the search picked one of those and
"scheduled" otherwise.

The search is one profile scan backwards from the door (`_Profile`): every hop
of every trip learns the soonest door arrival from riding it on. The options are
read off it at the stops the origin walks to, and each ride's backups - the
other ways to the door from where it boards - off the same scan at that stop,
so a backup is searched exactly as an option is.
"""
import bisect
import copy
import dataclasses
import datetime
import functools
import hashlib
import math
import pickle
import zoneinfo
from dataclasses import dataclass
from itertools import zip_longest
from pathlib import Path

import numpy as np

from . import gtfs, network, replay, walk as footpaths

DATA = Path(__file__).resolve().parent.parent / "data"
TRANSFERS = DATA / "transfers.npz"

TZ = zoneinfo.ZoneInfo("Europe/Kyiv")
DAY = 86400.0

# longest stop-to-stop walk kept in the cached transfer table, whose size is
# quadratic in it; the search's own limit is the pure walk
TRANSFER_CAP = 900.0

CHANGE = 60.0   # s of slack per change, over and above the walk

ROUNDS = 3      # rides per journey; a fourth round costs as much as the first three

# Each walk also capped to this many seconds, in slots of the scan of their
# own: the earliest arrival alone loses a ride from the door to a slightly
# faster one behind a long walk. Both caps here are at `walk.SPEED`; a search
# paced slower or faster keeps the distances and scales the seconds
WALK_CAPS = (600.0, 300.0)

LONGEST_WALK = 4 * 3600.0   # s past which the ends count as not joined on foot

# s before the forecast horizon within which a vehicle's last prediction counts
# as cut off by it rather than as the end of its line
HORIZON_EDGE = 300.0

# a route the schedule wanted QUIET_TRIPS times inside QUIET_WINDOW seconds,
# with nothing tracked on it since, is taken to not be running
QUIET_WINDOW = 3600.0
QUIET_TRIPS = 2

# s after the journey's arrival within which another way to the door still
# counts as a backup: missing the bus stings less when the next way is soon
BACKUP_WINDOW = 1800.0

# weakest first, so `min` over this order is the weakest ground a journey stands on
CONFIDENCE = ("quiet", "schedule", "live")


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

    # "live" is a vehicle being tracked, "schedule" is the timetable on a route
    # that is running, "quiet" is the timetable on one nothing has been seen on
    confidence: str = "live"


@dataclass(frozen=True, slots=True)
class Backup:
    """Another way to the door from where a ride boards: the rides it takes,
    the first leaving from there, when it reaches the door and the seconds it
    walks. `planned` is, per ride, the index of the journey's leg riding the
    same vehicle, or -1. `option` is the place in the list of the journey
    riding exactly these rides, or -1."""
    rides: tuple[Leg, ...]
    arr: float
    walk: float
    planned: tuple[int, ...]
    option: int = -1


@dataclass(frozen=True, slots=True)
class Journey:
    legs: tuple[Leg, ...]
    # per leg, the other ways to the door from where it boards
    backups: tuple[tuple[Backup, ...], ...] = ()

    @property
    def backup(self):
        """How many ways back up the weakest ride, for the ranking to prefer.
        One catching that ride's own vehicle further along is no help when it
        does not come, so it does not count."""
        return min((sum(i not in b.planned for b in backs)
                    for i, (leg, backs) in enumerate(zip(self.legs,
                                                         self.backups))
                    if leg.kind == "ride"), default=0)

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

    @property
    def walking(self):
        return sum(leg.arr - leg.dep for leg in self.legs if leg.kind == "walk")

    @property
    def confidence(self):
        """The weakest ground any ride in it stands on."""
        return min((leg.confidence for leg in self.legs if leg.kind == "ride"),
                   key=CONFIDENCE.index, default="live")


class Pattern:
    """Every trip that calls at the same stops in the same order.

    `times` is one row per trip, one column per stop, in seconds since the
    service day's midnight, rows sorted by departure. `service` indexes each
    row's service into `Timetable.services`; a pattern of a single day
    (`Timetable.on`) has none.
    """

    __slots__ = ("route", "stops", "times", "service")

    def __init__(self, route, stops, times, service=None):
        self.route = route
        self.stops = np.asarray(stops, dtype=np.int32)
        self.times = np.asarray(times, dtype=np.float64)
        self.service = service

    def running(self, runs):
        """The trips running on the day before, the day and the day after -
        `runs` holding each day's services - as one day's pattern in seconds
        since its midnight. The day before's count only past that midnight."""
        before = self.times[runs[0][self.service]]
        times = np.concatenate((before[before[:, -1] >= DAY] - DAY,
                                self.times[runs[1][self.service]],
                                self.times[runs[2][self.service]] + DAY))
        return Pattern(self.route, self.stops,
                       times[np.argsort(times[:, 0], kind="stable")])


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
    """The scheduled city, as trips grouped into patterns.

    Stops are indexed by `sorted(net.stops)` and `stop_i` maps a feed id into
    that; the live side keys by the catalog's order instead, so callers must
    translate.

    It holds every trip of every service; a search reads the one day it runs
    on, from `on`.
    """

    VERSION = 3

    def __init__(self, net):
        self.version = self.VERSION
        self.net = net
        self.stops = sorted(net.stops)
        self.stop_i = {s: i for i, s in enumerate(self.stops)}
        self.calendar = gtfs.Calendar()
        of = {t["trip_id"]: t["service_id"] for t in gtfs.table("trips.txt")}
        self.services = sorted(set(of.values()))
        service_i = {s: i for i, s in enumerate(self.services)}
        by_key = {}
        for trip, (stops, _, sched) in net.trip_stops.items():
            route = net.trip_route.get(trip)
            if route is None or len(stops) < 2 or trip not in of:
                continue
            key = (route, tuple(stops))
            by_key.setdefault(key, []).append((sched, service_i[of[trip]]))
        self.patterns = []
        for (route, stops), rows in by_key.items():
            times = np.array([r[0] for r in rows], dtype=np.float64)
            order = np.argsort(times[:, 0], kind="stable")
            idx = [self.stop_i[s] for s in stops]
            self.patterns.append(Pattern(
                route, idx, times[order],
                np.array([r[1] for r in rows], dtype=np.int32)[order]))

    def on(self, midnight):
        """The timetable as it runs on the day starting at `midnight`, unix
        seconds; see `Pattern.running`."""
        return _day(self, midnight)

    @functools.cached_property
    def by_route(self):
        out = {}
        for pat in self.patterns:
            out.setdefault(pat.route, []).append(pat)
        return out

    @property
    def lat(self):
        return np.array([self.net.stops[s]["lat"] for s in self.stops])

    @property
    def lon(self):
        return np.array([self.net.stops[s]["lon"] for s in self.stops])


@functools.lru_cache(maxsize=3)
def _day(tt, midnight):
    day = datetime.datetime.fromtimestamp(midnight, TZ).date()
    runs = [np.array([tt.calendar.runs(s, day + datetime.timedelta(days=d))
                      for s in tt.services], dtype=bool) for d in (-1, 0, 1)]
    out = copy.copy(tt)
    out.__dict__.pop("by_route", None)
    out.patterns = [pat.running(runs) for pat in tt.patterns]
    return out


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
    start = [0]
    to, cost = [], []
    for i in range(len(node)):
        if node[i] < 0:
            start.append(len(to))
            continue
        seen = walk.reach([(int(node[i]), 0.0)], cap)
        for j, t in _at_stops(seen, node, cap).items():
            if j != i:
                to.append(j)
                cost.append(t)
        start.append(len(to))
    path.parent.mkdir(parents=True, exist_ok=True)
    # beside the one held and swapped in, as a running service may read it
    fresh = path.with_name(path.stem + ".next.npz")
    np.savez_compressed(fresh, node=node,
                        to=np.array(to, dtype=np.int32),
                        cost=np.array(cost, dtype=np.float32),
                        start=np.array(start, dtype=np.int64),
                        model=np.array(walk.model),
                        graph=np.array(walk.graph),
                        stops=np.array(_stops_digest(tt)))
    fresh.replace(path)
    return path


def _stops_digest(tt):
    """The stops a transfer table is numbered against, and where they stand."""
    h = hashlib.blake2b(digest_size=16)
    h.update("\n".join(tt.stops).encode())
    h.update(tt.lat.tobytes())
    h.update(tt.lon.tobytes())
    return h.hexdigest()


class Transfers:
    __slots__ = ("node", "to", "cost", "start", "model", "graph", "stops")

    def __init__(self, node, to, cost, start, model, graph="", stops=""):
        self.node, self.to, self.cost, self.start = node, to, cost, start
        # the `Walk.model` and `Walk.graph` it was walked on, and the stops
        # it was walked between; empty in a table from before they were noted
        self.model, self.graph, self.stops = model, graph, stops

    @classmethod
    def load(cls, path=TRANSFERS):
        if not path.exists():
            raise FileNotFoundError(
                f"{path} is not there - run `python -m commuterlviv plan "
                "--build` once to walk between every pair of stops")
        with np.load(path) as z:
            return cls(z["node"], z["to"], z["cost"], z["start"],
                       *(str(z[k]) if k in z.files else ""
                         for k in ("model", "graph", "stops")))

    def paced(self, pace):
        """The table for somebody walking `pace` times as long."""
        return Transfers(self.node, self.to, self.cost * pace, self.start,
                         self.model, self.graph, self.stops)

    def stale(self, tt, walk):
        """Why the table cannot be read against this timetable and walk, or
        None. It is numbered against the stop list it was built with, and a
        rebuilt network (a new feed, a changed override) may move, add or drop
        stops while keeping their number; and walked on one footpath graph,
        which a refetch replaces."""
        stops = len(self.start) - 1
        if stops != len(tt.stops) or len(self.node) != len(tt.stops):
            return f"it lists {stops} stops against {len(tt.stops)} in the timetable"
        if not self.stops or not self.graph:
            return "it predates noting the stops and footpaths it was walked on"
        if self.stops != _stops_digest(tt):
            return "the timetable's stops have changed since"
        if self.graph != walk.graph:
            return "the footpaths have been refetched since"
        if self.model != walk.model:
            return (f"it was walked at {self.model or 'an older model'}, "
                    f"the footpaths now at {walk.model}")
        return None

    def near(self, i, limit):
        # A table built against an older stop list is shorter than the
        # timetable; `load` refuses that combination, so reaching here means a
        # caller bug rather than a stale file - but a journey search must never
        # turn it into a 500, only into a missing walk.
        if i < 0 or i + 1 >= len(self.start):
            return
        lo, hi = self.start[i], self.start[i + 1]
        for k in range(lo, hi):
            t = float(self.cost[k])
            if t <= limit:
                yield int(self.to[k]), t


def live_trips(tt, arrivals, catalog, now, horizon=replay.HORIZON):
    """Every tracked vehicle as a one-trip pattern, plus the last time one calls
    at each (stop, route) pair. Scheduled departures up to then are the ones
    those vehicles are running, so the caller should suppress them."""
    trips, covered = [], {}
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
        if len(stops) < 2:
            continue
        route = catalog.routes[int(rows[0]["route"])]
        if times[-1] > now + horizon - HORIZON_EDGE:
            _run_on(tt, route, stops, times)
        for i, when in zip(stops, times):
            covered[(i, route)] = max(covered.get((i, route), -math.inf), when)
        trips.append(LiveTrip(route, int(veh), stops, times))
    return trips, covered


def _run_on(tt, route, stops, times):
    """Carries a vehicle cut off by the forecast horizon on to the end of its
    line, at the timetable's running times from its last predicted stop."""
    a, b = stops[-2], stops[-1]
    for pat in tt.by_route.get(route, ()):
        hit = np.flatnonzero((pat.stops[:-1] == a) & (pat.stops[1:] == b))
        # a pattern runs no trips on a day none of its services does
        if not len(hit) or not len(pat.times):
            continue
        j = int(hit[0]) + 1
        _, midnight = _seconds_since_midnight(times[-1])
        col = pat.times[:, j]
        row = pat.times[int(np.argmin(np.abs(col - (times[-1] - midnight))))]
        stops.extend(int(s) for s in pat.stops[j + 1:])
        times.extend(times[-1] + row[j + 1:] - row[j])
        return


def route_confidence(tt, live, sod, window=QUIET_WINDOW, expected=QUIET_TRIPS):
    """How much a scheduled departure on each route is worth believing.

    A route with a vehicle being tracked is "live". One with none is "quiet"
    when the schedule wanted at least `expected` trips out of it in the last
    `window` seconds and not one of them turned up, which is what a line nobody
    is running looks like from here; otherwise it is "schedule", because a route
    that runs twice an hour is silent between runs by design.
    """
    running = {trip.route for trip in live}
    due = {}
    for pat in tt.patterns:
        if pat.route in running:
            continue
        col = pat.times[:, 0]
        due[pat.route] = due.get(pat.route, 0) + int(
            np.count_nonzero((col >= sod - window) & (col <= sod)))
    return {route: "quiet" if n >= expected else "schedule"
            for route, n in due.items()}


def _reach(walk, lat, lon, limit):
    """Walking seconds from a point to every node, inf past `limit`."""
    return walk.reach([(i, walk.flat(d)) for d, i in walk.near(lat, lon)],
                      limit)


def _at_stops(seen, node, limit):
    """A reach read at the stops standing on its nodes: stop -> seconds."""
    t = np.where(node >= 0, seen[node], math.inf)
    ok = np.flatnonzero(t <= limit)
    return dict(zip(ok.tolist(), t[ok].tolist()))


def journeys(tt, walk, transfers, origin, dest, now, arrivals=None,
             catalog=None, rounds=ROUNDS, keep=8, assess=True):
    """Ranked journeys from `origin` to `dest` (both (lat, lon)) leaving at
    `now`, which may be in the future: the vehicles being tracked are still
    used, for as far ahead as their predictions reach.

    `assess` off leaves every scheduled route believed. Silence only means a
    route is not running when the departure is close enough that the vehicles
    on the road now are the ones that would carry it.

    Somebody slower or faster on foot than `walk.SPEED` is searched for with
    `walk` and `transfers` paced to them.
    """
    walked, seen = _walk_through(walk, origin, dest)
    limit = walked if walked is not None else TRANSFER_CAP * walk.pace
    access = _at_stops(seen, transfers.node, limit)
    egress = _at_stops(_reach(walk, *dest, limit), transfers.node, limit)
    if not access or not egress:
        return _only_walking(walked, now)

    sod, midnight = _seconds_since_midnight(now)
    tt = tt.on(midnight)
    live, covered = ([], {}) if arrivals is None else \
        live_trips(tt, arrivals, catalog, now)
    trust = (route_confidence(tt, live, sod)
             if assess and arrivals is not None else {})
    paced = [c * walk.pace for c in WALK_CAPS]
    caps = (limit, *(c for c in paced if c < limit))
    hi = now + (walked if walked is not None else LONGEST_WALK) + BACKUP_WINDOW
    for quiet in (False, True):
        hops, trips = _connections(tt, live, trust, now, midnight, hi, quiet)
        hops = _corridor(hops, transfers, egress, caps[0],
                         [(u, now + t) for u, t in access.items()], hi)
        scan = _Profile(hops, trips, trust, transfers, egress, caps, rounds,
                        covered)
        found = _rank(scan.backed(scan.options(access, now)) +
                      _only_walking(walked, now), keep, walked)
        if quiet or any(j.rides for j in found) or \
                "quiet" not in trust.values():
            return _listed(found)


def _walk_through(walk, origin, dest, ceiling=LONGEST_WALK):
    """Seconds to walk the whole way, or None if the ends are not connected on
    foot within `ceiling`. This bounds every other walk in the plan. Also the
    walk from `origin` to every node, whole up to that bound, or to `ceiling`.

    The limit starts at the straight-line time, which the streets can only be
    longer than, and doubles until the search lands; an uncapped Dijkstra would
    walk the whole city.
    """
    goal = [(i, walk.flat(d)) for d, i in walk.near(*dest)]
    limit = max(walk.flat(footpaths.metres(*origin, *dest)) * 1.3, 300.0)
    while True:
        seen = _reach(walk, *origin, limit)
        walked = min((float(seen[i]) + t for i, t in goal), default=math.inf)
        if walked <= limit:
            return walked, seen
        if limit >= ceiling:
            return None, seen
        limit = min(limit * 2, ceiling)


def _only_walking(walked, now):
    if walked is None:
        return []
    return [Journey((Leg("walk", now, now + walked, -1, -1),))]


def _score(j):
    return j.arr, -j.backup, j.rides, j.walking


class _Profile:
    """The search: a profile connection scan (Dibbelt, Pajor, Strasser and
    Wagner, 2013) run backwards from the door, in which every hop of every
    trip, latest first, learns the earliest door arrival from riding it in at
    most 1, 2 ... `rounds` rides, with every walk capped at each of `caps`
    (longest first) - one scan for all the caps, the i-th at slot
    `i * rounds + rides - 1` - and each stop keeps the departures worth
    boarding.

    Tracked vehicles ride at their predictions, and a scheduled departure a
    tracked vehicle is running is not boarded.
    """

    def __init__(self, hops, trips, trust, transfers, egress, caps, rounds,
                 covered):
        self.hops, self.trips, self.trust = hops, trips, trust
        self.transfers, self.egress = transfers, egress
        self.caps, self.rounds = caps, rounds
        self.n = n = len(caps) * rounds
        none = ((math.inf,) * n, (None,) * n)
        stay = {}       # trip -> per slot, door arrival riding on, and how
        # hop -> the same, how being (alighted, next (hop, slot), walked)
        self.via = {}
        # stop -> latest first: -departure, (door, hop)
        self.deps, self.profile = {}, {}
        self.steps = {}     # stop -> (seconds to board, stop, walked, caps allowing it)
        self.boards = []    # every (stop, departure, hop) boarded
        for c, (u, v, d, a, t) in enumerate(zip(*hops)):
            door, how = map(list, stay.get(t, none))
            self._alight(c, v, a, door, how)
            self._fewer(door, how)
            self._change(c, v, a, door, how)
            self._fewer(door, how)
            if door[rounds - 1] == math.inf:
                continue
            door, how = tuple(door), tuple(how)
            stay[t] = self.via[c] = door, how
            route, veh = trips[t]
            if veh is not None or d > covered.get((u, route), -math.inf):
                self._board(u, d, c, door)

    def _alight(self, c, v, a, door, how):
        """Off hop `c` at `v` and on foot to the door: a first ride."""
        if (e := self.egress.get(v)) is None:
            return
        rounds = self.rounds
        for cap in range(sum(e <= x for x in self.caps)):
            if a + e < door[cap * rounds]:
                door[cap * rounds], how[cap * rounds] = a + e, (c, None, e)

    def _change(self, c, v, a, door, how):
        """Off hop `c` at `v` and onto the best departure worth boarding at a
        stop in reach: a ride more than that departure's."""
        rounds, deps, profile = self.rounds, self.deps, self.profile
        if (steps := self.steps.get(v)) is None:
            steps = self.steps[v] = sorted(
                (x + CHANGE, w, x, sum(x <= y for y in self.caps))
                for w, x in [(v, 0.0), *self.transfers.near(v, self.caps[0])])
        for x, w, walk, ok in steps:
            # a slot of a shorter cap is never ahead of a longer one's
            if a + x >= door[(ok - 1) * rounds + 1]:
                break
            at = deps.get(w)
            if at is None or at[0] > -(a + x):
                continue
            then, hop = profile[w][bisect.bisect_right(at, -(a + x)) - 1]
            for i in range(ok * rounds):
                if i % rounds and then[i - 1] < door[i]:
                    door[i], how[i] = then[i - 1], (c, (hop[i - 1], i - 1), walk)

    def _fewer(self, door, how):
        """A slot no better than the one with a ride fewer takes that one."""
        rounds = self.rounds
        for i in range(self.n):
            if i % rounds and door[i - 1] <= door[i]:
                door[i], how[i] = door[i - 1], how[i - 1]

    def _board(self, u, d, c, door):
        """Hop `c`, leaving `u` at `d`, among the departures worth boarding
        there if it beats every later one in some slot."""
        self.boards.append((u, d, c))
        at, got = self.deps.setdefault(u, []), self.profile.setdefault(u, [])
        if got:
            last, hop = got[-1]
            best = tuple(map(min, door, last))
            if best == last:
                return
            hop = tuple(c if x < y else h for x, y, h in zip(door, last, hop))
            door = best
        else:
            hop = (c,) * self.n
        if at and at[-1] == -d:
            got[-1] = door, hop
        else:
            at.append(-d)
            got.append((door, hop))

    def chain(self, c, i):
        """The way boarding hop `c` at slot `i`: per ride, the hop boarded,
        the hop alighted from and the seconds walked after it."""
        out = []
        while c is not None:
            e, nxt, walked = self.via[c][1][i]
            out.append((c, e, walked))
            c, i = nxt or (None, 0)
        return tuple(out)

    def ride(self, c, e):
        dep_s, arr_s, dep_t, arr_t, trip_of = self.hops
        route, veh = self.trips[trip_of[c]]
        return Leg("ride", dep_t[c], arr_t[e], dep_s[c], arr_s[e], route, veh,
                   veh is not None, "live" if veh is not None
                   else self.trust.get(route, "schedule"))

    def options(self, access, now):
        """For each slot, the soonest door arrival from a stop the origin
        walks to, the shortest walk winning a tie, as a journey with its way."""
        best = {}
        for u, t in sorted(access.items(), key=lambda x: x[1]):
            at = self.deps.get(u)
            if at is None or at[0] > -(now + t):
                continue
            door, hop = self.profile[u][bisect.bisect_right(at, -(now + t)) - 1]
            for i in range(sum(t <= x for x in self.caps) * self.rounds):
                if door[i] < best.get(i, (math.inf,))[0]:
                    best[i] = door[i], u, t, hop[i]
        found = {}
        for i, (_, u, t, c) in best.items():
            way = self.chain(c, i)
            if (u, way) not in found:
                legs = [Leg("walk", now, now + t, -1, u)]
                for k, (c, e, walked) in enumerate(way):
                    legs.append(ride := self.ride(c, e))
                    to = self.hops[0][way[k + 1][0]] if k + 1 < len(way) else -1
                    if to != ride.b:
                        legs.append(Leg("walk", ride.arr, ride.arr + walked,
                                        ride.b, to))
                found[(u, way)] = Journey(tuple(legs)), way
        return list(found.values())

    def backed(self, found):
        """Each journey with, per leg, the other ways to the door from where the
        leg boards: leaving after the chosen departure, reaching the door within
        BACKUP_WINDOW of the journey's arrival, and searched as the journey was.
        So a route parting from the chosen one short of the door counts, and so
        does one needing a change; the chosen route's next run counts, the
        chosen departure itself not, so a last bus of the day has none. Walks
        have none.

        Each sequence of routes counts once, at its soonest run. A way another
        beats - leaving no sooner, reaching the door no later, in no more rides,
        walking no more and riding no more of the journey's own vehicles - is
        left out: nobody changes twice to arrive with the bus they could have
        waited for.
        """
        after = {}
        for j, _ in found:
            for leg in j.legs:
                if leg.kind == "ride":
                    after[leg.a] = min(leg.dep, after.get(leg.a, math.inf))
        ways = {u: {} for u in after}
        rounds = self.rounds
        for u, d, c in self.boards:
            if d <= after.get(u, math.inf):
                continue
            door = self.via[c][0]
            for i, arr in enumerate(door):
                if arr == math.inf or i % rounds and arr == door[i - 1]:
                    continue
                way = self.chain(c, i)
                ways[u].setdefault(way, (d, arr, sum(w for *_, w in way)))
        return [dataclasses.replace(j, backups=self._backups(j, way, ways))
                for j, way in found]

    def _backups(self, j, way, ways):
        trip_of = self.hops[4]
        mine = dict(zip((trip_of[c] for c, *_ in way),
                        (i for i, leg in enumerate(j.legs) if leg.kind == "ride")))
        out = []
        for leg in j.legs:
            runs = {}
            for back, (d, arr, walked) in ways.get(leg.a, {}).items():
                if leg.kind == "ride" and leg.dep < d and \
                        arr <= j.arr + BACKUP_WINDOW:
                    routes = tuple(self.trips[trip_of[c]][0] for c, *_ in back)
                    runs.setdefault(routes, []).append((d, arr, walked, back))
            scored = []
            for held in runs.values():
                first = min(held)[0]
                for d, arr, walked, back in held:
                    if d == first:
                        planned = tuple(mine.get(trip_of[c], -1)
                                        for c, *_ in back)
                        scored.append(((d, arr, len(back), walked,
                                        sum(i >= 0 for i in planned)),
                                       back, planned))
            # whatever beats a way sorts before it, so the kept ones are
            # all it needs checking against
            scored.sort(key=lambda s: (-s[0][0], s[0][1:]))
            kept = []
            for s in scored:
                if not any(_beats(k[0], s[0]) for k in kept):
                    kept.append(s)
            out.append(tuple(
                Backup(tuple(self.ride(c, e) for c, e, _ in back), score[1],
                       score[3], planned)
                for score, back, planned in sorted(kept)))
        return tuple(out)


def _listed(found):
    """Marks each backup riding exactly what a listed journey rides with that
    journey's place in the list."""
    at = {tuple(leg for leg in j.legs if leg.kind == "ride"): n
          for n, j in enumerate(found)}

    def mark(backs):
        return tuple(dataclasses.replace(b, option=at.get(b.rides, -1))
                     for b in backs)

    return [dataclasses.replace(j, backups=tuple(map(mark, j.backups)))
            for j in found]


def _beats(a, b):
    """Whether backup score `a` - departure, door arrival, rides, seconds
    walked, rides on the journey's vehicles - is another than `b` and nowhere
    worse, leaving later being better."""
    return a != b and a[0] >= b[0] and all(x <= y for x, y in zip(a[1:], b[1:]))


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
    trip), with each trip's (route, vehicle) - the timetable's have none.
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
            trips += [(pat.route, None)] * len(rows)
    for trip in live:
        parts.append(_hops(trip.stops, trip.times[None], len(trips)))
        trips.append((trip.route, trip.veh))
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


def _rank(found, keep, walked=None):
    """Soonest first, keeping every journey no other one beats outright.

    Beaten means another is at least as good on arrival, on changes, on
    seconds spent walking and on backups: a slower journey every ride of
    which has another way behind it survives alongside the fastest hanging on
    one vehicle, which is the whole point of offering more than the fastest.
    Anything not faster than walking the way is dropped, the pure walk itself
    excepted.

    A journey riding a route nothing has been seen on is held back unless it is
    the only way of riding at all: better to be told to walk than to be sent to
    wait for a bus the city is not running. `journeys` searches those routes
    only when nothing else rides.
    """
    ceiling = math.inf if walked is None else walked
    found.sort(key=_score)
    out = []
    for j in found:
        if j.rides and j.arr - j.dep >= ceiling:
            continue
        if any(all(a <= b for a, b in zip(_score(o), _score(j))) for o in out):
            continue
        out.append(j)
    solid = [j for j in out if j.confidence != "quiet"]
    return (solid if any(j.rides for j in solid) else out)[:keep]


def load(net=None):
    """The three pieces a search needs; the timetable is built and cached here."""
    net = net or network.load()
    cache = DATA / "timetable.pkl"
    tt = None
    if cache.exists() and cache.stat().st_mtime >= Path(network.CACHE).stat().st_mtime:
        with open(cache, "rb") as fh:
            tt = pickle.load(fh)
    if getattr(tt, "version", 0) != Timetable.VERSION:
        tt = Timetable(net)
        with open(cache, "wb") as fh:
            pickle.dump(tt, fh, protocol=5)
    walk, transfers = footpaths.load(), Transfers.load()
    if why := transfers.stale(tt, walk):
        raise FileNotFoundError(
            f"{TRANSFERS} is stale: {why} - run `python -m commuterlviv plan "
            "--build` once to walk between every pair of stops")
    return tt, walk, transfers


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
        for leg, backs in zip_longest(j.legs, j.backups, fillvalue=()):
            where = ("the door" if leg.b < 0
                     else net.stops[tt.stops[leg.b]]["name"])
            if leg.kind == "walk":
                print(f"  walk {(leg.arr - leg.dep) / 60:.0f} min to {where}")
            else:
                short = net.routes[leg.route]["short"]
                tag = "live" if leg.live else "timetable"
                print(f"  {_clock(leg.dep)} {short} to {where} "
                      f"({_clock(leg.arr)}, {tag})")
                for back in backs:
                    shorts = " > ".join(net.routes[r.route]["short"]
                                        for r in back.rides)
                    also = (f", option {back.option + 1}"
                            if back.option >= 0 else "")
                    print(f"    or {_clock(back.rides[0].dep)} {shorts}, "
                          f"at the door {_clock(back.arr)}{also}")


def _clock(t):
    return datetime.datetime.fromtimestamp(t, TZ).strftime("%H:%M")


if __name__ == "__main__":  # pragma: no cover - the CLI entry does this
    import sys
    main(sys.argv[1:])
