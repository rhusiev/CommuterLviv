"""When a vehicle in at a terminus sets off on its next trip, by route.

A vehicle in early does not always wait for its timetabled departure. Over
the 14 days of Lviv's recording to 2026-10-07 (64761 early turnarounds) trams
and trolleybuses mostly do - on most lines 85-90% left within a minute of the
timetable - but bus routes differ widely, and on half of them at most one in
five waited: the rest set off minutes, up to half an hour, ahead of it. How
far ahead depends on the route and the terminus far more than on how long the
vehicle has stood, so each route keeps its recent turnarounds at each
terminus, and the next trip is timed by what they did: the timetable where it
is kept, otherwise halfway between as far ahead of it as those that left early
went and as far ahead as the last one went. Asked every minute of every early
stand of the last three of those days, that took the departure's mean error
from 10.34 to 6.02 minutes, and the share foretold over two minutes after the
vehicle had gone from 50% to 17%. Either half alone came to 6.4-6.5 minutes;
the time since the vehicle got in, or since the route last left there
whatever its vehicle had done, did worse.
"""
import collections
import datetime

import numpy as np

TURN = 120.0        # s at least between reaching a terminus and leaving it
KEEP = 50           # recent turnarounds kept per route and terminus
NEED = 10           # of them before the route's own habit is believed
WAITS = 0.5         # share that waited for the timetable for it to count as kept
WAITED = 60.0       # s before the timetable a departure can be and still have waited
# the upper quartile of how far ahead early departures went: one foretold
# early costs the rider a wait, one foretold late costs the vehicle. Chosen,
# not derived
QUANTILE = 0.75
STILL = 3           # departures still ahead of now before they are believed
AT_END = 60.0       # m short of the last stop within which a vehicle is in
AWAY = 100.0        # m past the first stop by which it has left
STRAY = 1000.0      # m past it beyond which a fix is a loop's far end, not leaving
DAY = 86400.0
FIELDS = ("route", "stop", "waited", "ahead")    # what `export` gives, in order


class Layovers:
    """Turnarounds as they happen, and the departures they imply."""

    def __init__(self, net, tz):
        self.net = net
        self.tz = tz
        self.seen = {}       # (route, first stop) -> deque of (waited, s ahead)
        self._on = {}        # veh -> [trip, been away from its end, time in]
        self._out = {}       # veh in early -> its timetabled departure, until it leaves

    def follow(self, veh, tr):
        """Called after every fix `track.observe` folded into `tr`."""
        if tr.s is None:
            return
        on = self._on.get(veh)
        if on is None or on[0] != tr.trip:
            self._out.pop(veh, None)
            if on is not None and on[2] is not None \
                    and self.net.trip_next.get(on[0]) == tr.trip:
                sched = clock(tr.sched[0], tr.ts, self.tz)
                if on[2] + TURN < sched:
                    self._out[veh] = sched
            on = self._on[veh] = [tr.trip, False, None]
        if tr.s < tr.sdist[-1] - AT_END:
            on[1] = True
        elif on[1] and on[2] is None:
            on[2] = tr.ts
        sched = self._out.get(veh)
        if sched is not None and AWAY <= tr.s - tr.sdist[0] <= STRAY:
            del self._out[veh]
            self.see(self._key(tr.trip), tr.ts - sched > -WAITED, sched - tr.ts)

    def _key(self, trip):
        return self.net.trip_route[trip], self.net.trip_stops[trip][0][0]

    def see(self, key, waited, ahead):
        got = self.seen.get(key)
        if got is None:
            got = self.seen[key] = collections.deque(maxlen=KEEP)
        got.append((bool(waited), float(ahead)))

    def came(self, veh, trip):
        """When this vehicle got to the end of `trip`, if it is in."""
        on = self._on.get(veh)
        return on[2] if on is not None and on[0] == trip else None

    def leave(self, trip, sched, ready, now):
        """When a vehicle in at `ready` sets off on `trip`, which the timetable
        has leave at `sched`, as seen at `now`: halfway between how far ahead
        the route's early departures go and how far ahead the last vehicle in
        early went. Only the departures that left after `now` count for the
        first: a vehicle still in after nearly all of them is waiting for the
        timetable after all."""
        soonest = max(now, ready + TURN)
        kept = max(sched, soonest)
        got = self.seen.get(self._key(trip))
        if ready + TURN >= sched or got is None or len(got) < NEED:
            return kept
        if np.mean([w for w, _ in got]) >= WAITS:
            return kept
        ahead = [a for w, a in got if not w and sched - a > now]
        habit = kept if len(ahead) < STILL else max(
            soonest, sched - float(np.quantile(ahead, QUANTILE)))
        last = max(soonest, sched - got[-1][1])
        return (habit + last) / 2

    def export(self):
        """The turnarounds as flat arrays, oldest first within a key."""
        rows = [(*k, w, a) for k, got in self.seen.items() for w, a in got]
        cols = list(zip(*rows)) or [()] * len(FIELDS)
        return dict(zip(FIELDS, (np.array(c, dtype=t) for c, t in
                                 zip(cols, (str, str, bool, float)))))

    def restore(self, route, stop, waited, ahead):
        self.seen.clear()
        for r, st, w, a in zip(route, stop, waited, ahead):
            self.see((str(r), str(st)), w, a)


def clock(sched, now, tz):
    """A timetable time - seconds past a service day's midnight, possibly
    over 24 h - as the unix instant nearest `now`."""
    local = datetime.datetime.fromtimestamp(now, tz)
    midnight = local.replace(hour=0, minute=0, second=0,
                             microsecond=0).timestamp()
    return min((midnight + k * DAY + sched for k in (-1, 0, 1)),
               key=lambda t: abs(t - now))
