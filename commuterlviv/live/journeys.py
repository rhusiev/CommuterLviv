"""The journey planner, as the service holds it.

Optional: without `data/walk.npz` and `data/transfers.npz` the endpoint answers
503 and everything else is untouched. `arrange` builds them once in the
background; COMMUTERLVIV_BUILD_PLANNER=false leaves that to the operator.

This is also where `plan.py`'s stop numbering is translated into the catalog's,
which is what the wire uses.
"""
import asyncio
import time
from itertools import zip_longest

import numpy as np
import requests

from .. import network, plan, replay, walk as footpaths
from . import geometry

DETAIL = 4.0    # m a drawn leg may stray from the real line


class Planner:
    def __init__(self, tt, walk, transfers, cat):
        self.tt, self.walk, self.transfers, self.cat = tt, walk, transfers, cat
        self.stop_i = [cat.stop_i.get(s, -1) for s in tt.stops]
        self.route_i = cat.route_i
        net = tt.net
        self.rides = {}     # route -> every distinct (shape, stop ids, dist)
        for trip, key in net.pattern_of.items():
            ids, dist, _ = net.trip_stops[trip]
            self.rides.setdefault(net.trip_route[trip], {})[key] = \
                (key[0], ids, dist)

    @classmethod
    def maybe(cls, net, cat, log):
        """The planner, or None with a line in the log saying what is missing."""
        try:
            tt, walk, transfers = plan.load(net)
        except FileNotFoundError as e:
            log(f"no journey planner: {e}")
            return None
        return cls(tt, walk, transfers, cat)

    def search(self, origin, dest, arrivals, now=None, speed=None):
        """Ranked journeys, on the wire, and as `plan` found them. Call it
        from a worker thread: a city-wide search is half a second of Python.
        `speed` is how fast the traveller walks on the level, in km/h,
        `walk.SPEED` by default.

        A `now` in the future still gets the vehicles being tracked: the search
        keeps only their arrivals that lie ahead of it, so a trip starting in
        ten minutes rides the same predictions an immediate one does. Past the
        model's horizon there are none left and the timetable takes over, which
        is also where judging a route quiet stops meaning anything.
        """
        now = time.time() if now is None else now
        found = self.journeys(origin, dest, arrivals, now, speed,
                              now <= time.time() + replay.HORIZON)
        path, between = self._drawing(origin, dest, arrivals, speed)
        return {"t": now,
                "options": [self.wire(j, path, between) for j in found]}, found

    def backup(self, origin, dest, arrivals, speed, j, leg, n):
        """Journey `j` taking the `n`-th backup of its `leg`-th leg as sent,
        on the wire as an option is: its legs up to the stop that one boards,
        then the backup's. None when `j` has no such backup."""
        if not 0 <= leg < len(j.backups):
            return None
        backs = self._sent(j.backups[leg])
        if not 0 <= n < len(backs):
            return None
        way = plan.Journey((*j.legs[:leg], *backs[n].legs()), j.backups[:leg])
        return self.wire(way, *self._drawing(origin, dest, arrivals, speed))

    def _drawing(self, origin, dest, arrivals, speed):
        """What `wire` draws legs and lists the stops of rides with."""
        walk = self._paced(speed)[0]
        # options share their first and last walks, so each is drawn once
        paths = {}

        def path(leg):
            key = (leg.kind, leg.route, leg.a, leg.b)
            if key not in paths:
                paths[key] = self._path(leg, origin, dest, arrivals, walk)
            return paths[key]

        def between(leg):
            return self._between(leg, arrivals)

        return path, between

    def journeys(self, origin, dest, arrivals, now, speed, assess):
        """`plan.journeys` for somebody walking at `speed`."""
        walk, transfers = self._paced(speed)
        return plan.journeys(self.tt, walk, transfers, origin, dest, now,
                             arrivals=arrivals, catalog=self.cat, assess=assess)

    def _paced(self, speed):
        if speed is None:
            return self.walk, self.transfers
        pace = footpaths.SPEED * 3.6 / speed
        return self.walk.paced(pace), self.transfers.paced(pace)

    def wire(self, j, path=None, between=None):
        """`j` as sent; without `path`, its legs are not drawn, and without
        `between` its rides do not say where they call on the way."""
        return {"dep": int(j.dep), "arr": int(j.arr), "rides": j.rides,
                "live": j.live, "confidence": j.confidence,
                "backup": j.backup,
                "legs": [self._leg(x, path, between, b) for x, b in
                         zip_longest(j.legs, j.backups, fillvalue=())]}

    def _leg(self, leg, path, between, backups):
        out = {"kind": leg.kind, "dep": int(leg.dep), "arr": int(leg.arr),
               "a": self.stop_i[leg.a] if leg.a >= 0 else -1,
               "b": self.stop_i[leg.b] if leg.b >= 0 else -1,
               "pts": path(leg) if path else []}
        if leg.kind == "ride":
            out["route"] = self.route_i.get(leg.route, -1)
            out["veh"] = leg.veh
            out["live"] = leg.live
            out["confidence"] = leg.confidence
            stops = between(leg) if between else None
            if stops is not None:
                out["stops"] = stops
            out["backups"] = [
                {"rides": [self._ride(r, p >= 0)
                           for r, p in zip(b.rides, b.planned)],
                 "arr": int(b.arr), "walk": int(b.walk), "option": b.option}
                for b in self._sent(backups)]
        return out

    def _sent(self, backups):
        """The backups the wire carries: those on routes the catalog has."""
        return [b for b in backups
                if all(r.route in self.route_i for r in b.rides)]

    def _ride(self, r, planned):
        return {"route": self.route_i[r.route], "dep": int(r.dep),
                "arr": int(r.arr), "a": self.stop_i[r.a], "b": self.stop_i[r.b],
                "live": r.live, "planned": planned}

    def _where(self, i, end):
        if i < 0:
            return end
        s = self.tt.net.stops[self.tt.stops[i]]
        return s["lat"], s["lon"]

    def _path(self, leg, origin, dest, arrivals, walk):
        """Where the leg goes: the footpath walked, or the stretch of the
        route's line between boarding and alighting."""
        return geometry.points(geometry.simplify(
            self._line(leg, origin, dest, arrivals, walk), DETAIL))

    def _line(self, leg, origin, dest, arrivals, walk):
        a, b = self._where(leg.a, origin), self._where(leg.b, dest)
        if leg.kind == "walk":
            limit = (leg.arr - leg.dep) * 1.5 + 60.0
            return network.to_xy(*np.array(walk.path(a, b, limit)).T)
        stretch = self._stretch(leg.route, leg.a, leg.b)
        if stretch is not None:
            return self._shape(*stretch)
        # A tracked vehicle keeps its wire id across the trips it runs next,
        # so one ride can span two patterns and no single shape covers it:
        # draw each stretch on its own shape, hopping straight only between
        # shapes (a layover at a terminus, usually the same place twice).
        seq = self._live_seq(leg, arrivals)
        if seq is not None:
            return np.vstack([self._piece(leg.route, u, v)
                              for u, v in zip(seq, seq[1:])])
        return network.to_xy(*np.array([a, b]).T)

    def _live_seq(self, leg, arrivals):
        """The vehicle's timetable-stop indexes in arrival order, cut to this
        ride; None when the ride is not a tracked vehicle's to draw."""
        if leg.veh is None or arrivals is None:
            return None
        seq = []
        for r in arrivals.of(int(leg.veh)):
            i = self.tt.stop_i.get(self.cat.stops[int(r["stop"])])
            if i is not None:
                seq.append(i)
        try:
            i0 = seq.index(leg.a)
            i1 = seq.index(leg.b, i0 + 1)
        except ValueError:
            return None
        return seq[i0:i1 + 1]

    def _piece(self, route, u, v):
        """The shape between two timetable stops, or straight across when no
        pattern runs one to the other."""
        stretch = self._stretch(route, u, v)
        if stretch is not None:
            return self._shape(*stretch)
        a, b = self._where(u, None), self._where(v, None)
        return network.to_xy(*np.array([a, b]).T)

    def _stretch(self, route, u, v):
        """The first of the route's patterns calling at timetable stop `u` and
        later at `v`: its (shape, stop ids, dist) and where in them the two
        are, or None."""
        at, to = self.tt.stops[u], self.tt.stops[v]
        for sid, ids, dist in self.rides.get(route, {}).values():
            if at not in ids or to not in ids[ids.index(at) + 1:]:
                continue
            i = ids.index(at)
            return sid, ids, dist, i, ids.index(to, i + 1)
        return None

    def _shape(self, sid, ids, dist, i, j):
        d0, d1 = dist[i], dist[j]
        shape = self.tt.net.shapes[sid]
        inner = shape.xy[(shape.cum > d0) & (shape.cum < d1)]
        return np.vstack([shape.at(d0), inner, shape.at(d1)])

    def _between(self, leg, arrivals):
        """The catalog stops a ride calls at after boarding and before getting
        off, in order, from the same pattern its line is drawn along; None
        when nothing says."""
        stretch = self._stretch(leg.route, leg.a, leg.b)
        if stretch is not None:
            _, ids, _, i, j = stretch
            inner = [self.cat.stop_i.get(s, -1) for s in ids[i + 1:j]]
        else:
            seq = self._live_seq(leg, arrivals)
            if seq is None:
                return None
            inner = [self.stop_i[k] for k in seq[1:-1]]
        return [k for k in inner if k >= 0]


def _make(net, log):
    """The two files, built where they are missing or stale: minutes on a
    volume with no footpaths, seconds otherwise. Without the elevation tiles
    the city is walked as if it were flat, and they are asked for again the
    next time."""
    if not footpaths.CACHE.exists():
        log("planner: asking Overpass for the city's footpaths, once")
        footpaths.save()
    if not footpaths.climbed():
        log("planner: fetching the city's elevation, once")
        try:
            footpaths.climb()
        except requests.RequestException as exc:
            log("planner: walking on the level for now -", repr(exc)[:200])
    tt, walk = plan.Timetable(net), footpaths.load()
    try:
        why = plan.Transfers.load().stale(tt, walk)
    except FileNotFoundError:
        why = "there is none"
    if why:
        log(f"planner: walking between every pair of stops, once - {why}")
        plan.build_transfers(tt, walk)


def ready(net, cat, log, build=True):
    """The planner for this network, or None. With `build` its files are
    built first where they are missing or stale; blocking, so run it in a
    thread."""
    if build:
        _make(net, log)
    return Planner.maybe(net, cat, log)


async def arrange(state, net, cat, log):
    """Build what is missing in a thread, then install the planner on the app
    state. A failure here disables one endpoint and never the service; while
    it runs, `state.preparing` says the planner is on its way."""
    state.preparing = True
    try:
        planner = await asyncio.to_thread(ready, net, cat, log)
        # a renew that landed meanwhile installed a planner for the newer city
        if cat is state.svc.live.cat:
            state.planner = planner
    except Exception as exc:
        log("planner: giving up on this start -", repr(exc)[:200])
    finally:
        state.preparing = False
    if state.planner:
        log("planner: ready")
