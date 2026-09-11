"""The journey planner, as the service holds it.

Optional: without `data/walk.npz` and `data/transfers.npz` the endpoint answers
503 and everything else is untouched. `arrange` builds them once in the
background; COMMUTERLVIV_BUILD_PLANNER=false leaves that to the operator.

This is also where `plan.py`'s stop numbering is translated into the catalog's,
which is what the wire uses.
"""
import asyncio
import time

from .. import plan, replay, walk as footpaths


class Planner:
    def __init__(self, tt, walk, transfers, cat):
        self.tt, self.walk, self.transfers, self.cat = tt, walk, transfers, cat
        self.stop_i = [cat.stop_i.get(s, -1) for s in tt.stops]
        self.route_i = cat.route_i

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
        return {"t": now, "options": [self._wire(j) for j in found]}

    def _wire(self, j):
        return {"dep": int(j.dep), "arr": int(j.arr), "rides": j.rides,
                "live": j.live, "confidence": j.confidence,
                "legs": [self._leg(x) for x in j.legs]}

    def _leg(self, leg):
        out = {"kind": leg.kind, "dep": int(leg.dep), "arr": int(leg.arr),
               "a": self.stop_i[leg.a] if leg.a >= 0 else -1,
               "b": self.stop_i[leg.b] if leg.b >= 0 else -1}
        if leg.kind == "ride":
            out["route"] = self.route_i.get(leg.route, -1)
            out["veh"] = leg.veh
            out["live"] = leg.live
            out["confidence"] = leg.confidence
        return out


def _make(net, log):
    """The two files, built where they are missing. Minutes, and blocking."""
    if not footpaths.CACHE.exists():
        log("planner: asking Overpass for the city's footpaths, once")
        footpaths.save()
    if not plan.TRANSFERS.exists():
        log("planner: walking between every pair of stops, once")
        plan.build_transfers(plan.Timetable(net), footpaths.load())


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
