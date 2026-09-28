"""The journey planner, as the service holds it.

Optional: without `data/walk.npz` and `data/transfers.npz` the endpoint answers
503 and everything else is untouched. `arrange` builds them once in the
background; COMMUTERLVIV_BUILD_PLANNER=false leaves that to the operator.

This is also where `plan.py`'s stop numbering is translated into the catalog's,
which is what the wire uses.
"""
import asyncio
import time

import numpy as np

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

    def search(self, origin, dest, arrivals, now=None):
        """Ranked journeys, on the wire. Call it from a worker thread: a
        city-wide search is most of a second of Python.

        A `now` in the future still gets the vehicles being tracked: the search
        keeps only their arrivals that lie ahead of it, so a trip starting in
        ten minutes rides the same predictions an immediate one does. Past the
        model's horizon there are none left and the timetable takes over, which
        is also where judging a route quiet stops meaning anything.
        """
        now = time.time() if now is None else now
        found = plan.journeys(self.tt, self.walk, self.transfers, origin, dest,
                              now, arrivals=arrivals, catalog=self.cat,
                              assess=now <= time.time() + replay.HORIZON)
        # options share their first and last walks, so each is drawn once
        paths = {}

        def path(leg):
            key = (leg.kind, leg.route, leg.a, leg.b)
            if key not in paths:
                paths[key] = self._path(leg, origin, dest, arrivals)
            return paths[key]

        return {"t": now, "options": [self._wire(j, path) for j in found]}

    def _wire(self, j, path):
        return {"dep": int(j.dep), "arr": int(j.arr), "rides": j.rides,
                "live": j.live, "confidence": j.confidence,
                "backup": j.backup,
                "legs": [self._leg(x, path) for x in j.legs]}

    def _leg(self, leg, path):
        out = {"kind": leg.kind, "dep": int(leg.dep), "arr": int(leg.arr),
               "a": self.stop_i[leg.a] if leg.a >= 0 else -1,
               "b": self.stop_i[leg.b] if leg.b >= 0 else -1,
               "pts": path(leg)}
        if leg.kind == "ride":
            out["route"] = self.route_i.get(leg.route, -1)
            out["veh"] = leg.veh
            out["live"] = leg.live
            out["confidence"] = leg.confidence
        return out

    def _where(self, i, end):
        if i < 0:
            return end
        s = self.tt.net.stops[self.tt.stops[i]]
        return s["lat"], s["lon"]

    def _path(self, leg, origin, dest, arrivals):
        """Where the leg goes: the footpath walked, or the stretch of the
        route's line between boarding and alighting."""
        return geometry.points(geometry.simplify(
            self._line(leg, origin, dest, arrivals), DETAIL))

    def _line(self, leg, origin, dest, arrivals):
        a, b = self._where(leg.a, origin), self._where(leg.b, dest)
        if leg.kind == "walk":
            limit = (leg.arr - leg.dep) * 1.5 + 60.0
            return network.to_xy(*np.array(self.walk.path(a, b, limit)).T)
        at, to = self.tt.stops[leg.a], self.tt.stops[leg.b]
        for sid, ids, dist in self.rides.get(leg.route, {}).values():
            if at not in ids or to not in ids[ids.index(at) + 1:]:
                continue
            i = ids.index(at)
            d0, d1 = dist[i], dist[ids.index(to, i + 1)]
            shape = self.tt.net.shapes[sid]
            inner = shape.xy[(shape.cum > d0) & (shape.cum < d1)]
            return np.vstack([shape.at(d0), inner, shape.at(d1)])
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
        at, to = self.tt.stops[u], self.tt.stops[v]
        for sid, ids, dist in self.rides.get(route, {}).values():
            if at not in ids or to not in ids[ids.index(at) + 1:]:
                continue
            i = ids.index(at)
            d0, d1 = dist[i], dist[ids.index(to, i + 1)]
            shape = self.tt.net.shapes[sid]
            inner = shape.xy[(shape.cum > d0) & (shape.cum < d1)]
            return np.vstack([shape.at(d0), inner, shape.at(d1)])
        a, b = self._where(u, None), self._where(v, None)
        return network.to_xy(*np.array([a, b]).T)


def _make(net, log):
    """The two files, built where they are missing or stale. Minutes, and
    blocking: `arrange` runs it in a thread.

    The transfer table is numbered against the stop list it was built with, so
    a rebuilt network (a new feed, a changed override) silently shortens or
    lengthens the timetable it is read against. Length is the whole check: the
    table carries one row per stop and nothing else keys it."""
    if not footpaths.CACHE.exists():
        log("planner: asking Overpass for the city's footpaths, once")
        footpaths.save()
    tt = plan.Timetable(net)
    try:
        transfers = plan.Transfers.load()
        fresh = len(transfers.start) - 1 == len(tt.stops) and \
            len(transfers.node) == len(tt.stops)
    except FileNotFoundError:
        fresh = False
    if not fresh:
        log("planner: walking between every pair of stops, once")
        plan.build_transfers(tt, footpaths.load())


async def arrange(state, net, cat, log):
    """Build what is missing in a thread, then install the planner on the app
    state. A failure here disables one endpoint and never the service."""
    try:
        await asyncio.to_thread(_make, net, log)
    except Exception as exc:
        log("planner: giving up on this start -", repr(exc)[:200])
        return
    state.planner = Planner.maybe(net, cat, log)
    if state.planner:
        log("planner: ready")
