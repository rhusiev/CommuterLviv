"""What actually happened, in a form every predictor can be asked about.

Ground truth is the moment a vehicle's tracked position crossed a stop's
position on the shape, interpolated between the two fixes either side of it.
It comes from the vehicle stream alone, so it is independent of every
predictor scored against it.

The awkward part is naming. One crossing is one *event*, but the predictors
do not agree on how to address it: our own model and the API's trip_updates
name a trip and a stop, while the arrivals board names a vehicle and a stop
and never says which trip the vehicle is running. An event is kept only if
both namings pick it out uniquely - a trip served by two vehicles at once, or
a vehicle passing the same stop twice, is dropped from all four predictors
together. After that a single event number means the same crossing to
everyone, which is what makes a paired comparison possible at all.
"""
import numpy as np


class Truth:
    """Unambiguous crossing events, addressable by any predictor's naming."""

    def __init__(self, net, res):
        by_trip = _unique((ti, si) for (_, ti, _, si) in res.truth)
        by_veh = _unique((vi, net.trip_stops[res.trip_ids[ti]][0][si])
                         for (vi, ti, _, si) in res.truth)

        self.time = []          # event -> crossing time
        self.gap = []           # event -> width of the interpolated interval
        self.trip = []          # event -> trip index, for resampling by trip
        self.by_trip_stop = {}  # (trip index, stop position) -> event
        self.by_veh_stop = {}   # (vehicle index, stop id) -> event
        for key, t in res.truth.items():
            vi, ti, _, si = key
            kt = (ti, si)
            kv = (vi, net.trip_stops[res.trip_ids[ti]][0][si])
            if kt not in by_trip or kv not in by_veh:
                continue
            e = len(self.time)
            self.time.append(t)
            self.gap.append(res.gap[key])
            self.trip.append(ti)
            self.by_trip_stop[kt] = e
            self.by_veh_stop[kv] = e
        self.time = np.array(self.time)
        self.gap = np.array(self.gap)
        self.trip = np.array(self.trip, dtype=np.int64)
        self.n = len(self.time)


def _unique(keys):
    """The keys that occur exactly once. Anything repeated is ambiguous."""
    seen, dup = set(), set()
    for k in keys:
        (dup if k in seen else seen).add(k)
    return seen - dup
