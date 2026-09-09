"""The journey planner, as the service holds it.

`plan.py` does the search and knows nothing about the wire; this owns the two
things the service has to decide about it.

It is optional. The search needs `data/walk.npz` and `data/transfers.npz`,
which are built by hand and are not in the checkout, so a service without them
answers 503 on this one endpoint and serves everything else exactly as before.

And it speaks the client's indices. `plan.py` numbers stops in its own order;
everything on the wire is numbered in the catalog's. The translation lives here
rather than in either of them, so neither has to assume the other's ordering.
"""
import time

from .. import plan


class Planner:
    def __init__(self, tt, walk, transfers, cat):
        self.tt, self.walk, self.transfers, self.cat = tt, walk, transfers, cat
        self.stop_i = [cat.stop_i.get(s, -1) for s in tt.stops]
        self.route_i = cat.route_i

    @classmethod
    def maybe(cls, net, cat, log):
        """The planner, or None with a line in the log saying what is missing.
        A checkout that has never fetched the footpaths still serves the map."""
        try:
            tt, walk, transfers = plan.load(net)
        except FileNotFoundError as e:
            log(f"no journey planner: {e}")
            return None
        return cls(tt, walk, transfers, cat)

    def search(self, origin, dest, arrivals, now=None):
        """Ranked journeys, on the wire. Runs in a worker thread - a city-wide
        search is most of a second of Python, and a frame budget is 16 ms."""
        now = now or time.time()
        found = plan.journeys(self.tt, self.walk, self.transfers, origin, dest,
                              now, arrivals=arrivals, catalog=self.cat)
        return {"t": now, "options": [self._wire(j) for j in found]}

    def _wire(self, j):
        return {"dep": int(j.dep), "arr": int(j.arr), "rides": j.rides,
                "live": j.live, "legs": [self._leg(x) for x in j.legs]}

    def _leg(self, leg):
        out = {"kind": leg.kind, "dep": int(leg.dep), "arr": int(leg.arr),
               "a": self.stop_i[leg.a] if leg.a >= 0 else -1,
               "b": self.stop_i[leg.b] if leg.b >= 0 else -1}
        if leg.kind == "ride":
            out["route"] = self.route_i.get(leg.route, -1)
            out["veh"] = leg.veh
            out["live"] = leg.live
        return out
