"""What actually happened, in a form every predictor can be asked about.

Ground truth is the moment a vehicle's tracked position crossed a stop's
position on the shape, interpolated between the two fixes either side of it.
It comes from the vehicle stream alone, so it is independent of every
predictor scored against it.

The awkward part is naming. One crossing is one *event*, and a crossing is
named in full by the vehicle, the trip, which pass of that trip it was on, and
which stop - but no predictor says all four. Ours does, because it is our own
tracker that assigns them. The API's trip_updates names a trip and a stop; the
arrivals board names a vehicle and a stop and never says which trip or which
pass. Neither says which pass, and over a night and a morning a vehicle passes
each of its stops many times, so a name on its own can stand for a dozen
crossings.

What settles it is *when* the prediction was made. A board that says "arrives
in 4 minutes" at 20:31 is talking about the next crossing at or after 20:31,
not about one eleven hours later. So each naming is an `Index`, asked with a
key and an instant, and the crossing it returns is the next one. That rule uses
only the time the predictor spoke, never the value it gave, so it cannot be
tuned to flatter anybody.

The alternative - keeping only the crossings a name happens to pick out
uniquely - was what this file used to do, and it threw away 89% of the ground
truth to accommodate the one predictor that answers about 40 stops.
"""
import bisect

import numpy as np


class Truth:
    """Every crossing, plus one index per naming that predictors can address."""

    def __init__(self, net, res):
        keys = list(res.truth)
        self.time = np.array([res.truth[k] for k in keys])
        self.gap = np.array([res.gap[k] for k in keys])
        self.trip = np.array([k[1] for k in keys], dtype=np.int64)
        self.n = len(self.time)

        # The full name of a crossing, and the two partial ones.
        self.event = {k: e for e, k in enumerate(keys)}
        self.by_trip_stop = Index(((ti, si) for (_, ti, _, si) in keys), self.time)
        self.by_veh_stop = Index(
            ((vi, net.trip_stops[res.trip_ids[ti]][0][si])
             for (vi, ti, _, si) in keys), self.time)


class Index:
    """The crossings one partial name stands for, in time order.

    Built from one name per crossing, in event order, so the n-th name is the
    name event n goes by.
    """

    def __init__(self, names, time):
        self._by_key = {}
        for e, key in enumerate(names):
            self._by_key.setdefault(key, []).append((float(time[e]), e))
        for v in self._by_key.values():
            v.sort()

    def at(self, key, t):
        """The crossing whoever spoke at `t` meant: the next one, or None."""
        v = self._by_key.get(key)
        if v is None:
            return None
        i = bisect.bisect_left(v, (t,))
        return v[i][1] if i < len(v) else None

    def __iter__(self):
        for key, v in self._by_key.items():
            for _, e in v:
                yield key, e

    def __len__(self):
        return len(self._by_key)
