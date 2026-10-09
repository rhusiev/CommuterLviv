"""When a vehicle in at a terminus sets off on its next trip, by route.

A vehicle in early does not always wait for its timetabled departure. Over
the 14 days of Lviv's recording to 2026-10-07 (64761 early turnarounds) trams
and trolleybuses mostly do - on most lines 85-90% left within a minute of the
timetable - but bus routes differ widely, and on half of them at most one in
five waited: the rest set off minutes, up to half an hour, ahead of it. How
far ahead depends on the route and the terminus far more than on how long the
vehicle has stood, so each route keeps its recent turnarounds at each
terminus. Those give a rule: the timetable where it is kept, otherwise halfway
between as far ahead of it as those that left early went and as far ahead as
the last one went. A model learned from the minutes of past stands (`fit`)
weighs the same evidence - the rule's two halves, the route's last departure,
the timetable's gap, the hour - and takes over from the rule once it has
enough of them. Asked every minute of every early stand of the last three of
those days, the timetable was out by 10.34 minutes on average, the rule by
6.02 and the model, learning as it went, by 5.14, with the share foretold
over two minutes after the vehicle had gone at 50%, 17% and 17%.
"""
import collections
import datetime

import numpy as np
from sklearn.ensemble import HistGradientBoostingRegressor

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

# the model: a minute of an early stand is one row, its target the seconds
# from that minute to the departure. ~75 000 rows a day in Lviv
ROWS = 500_000      # newest rows kept to learn from, about a week
FIT_ROWS = 50_000   # sampled from them into a fit, ~12 s of CPU
NEED_ROWS = 20_000  # before a fitted model is trusted over the rule
# the quantile foretold: below the median, which was as often late as the
# rule is (17%) where the median was late 23% of the time. Chosen, not derived
LEAN = 0.4
ITERS = 300
RATE = 0.05
PENDING = 6 * 3600.0    # s a stand's rows wait for its departure before dropped
FEATURES = ("in for", "to timetable", "slack", "waited share", "kept", "ahead q25",
            "ahead q50", "ahead q75", "since last left", "timetable gap",
            "last ahead", "habit", "after last", "after last early", "hour")


class Layovers:
    """Turnarounds as they happen, and the departures they imply."""

    def __init__(self, net, tz):
        self.net = net
        self.tz = tz
        self.seen = {}       # (route, first stop) -> deque of (waited, s ahead)
        self.last = {}       # (route, first stop) -> (departure, timetabled) of its latest
        self._rows = np.zeros((ROWS, len(FEATURES) + 1), dtype=np.float32)
        self._wrote = 0      # rows ever written; the ring keeps the last `ROWS`
        self.model = None
        self._on = {}        # veh -> [trip, been away from its end, time in]
        self._out = {}       # veh -> (timetabled departure, in early), until it leaves
        self._asked = {}     # trip -> [(time, features)] of its stand, until it leaves
        self._batch = []     # this epoch's stands: (trip, soonest, features)
        self._foretold = {}  # trip -> when the model has it leave, this epoch

    def follow(self, veh, tr):
        """Called after every fix `track.observe` folded into `tr`."""
        if tr.s is None:
            return
        on = self._on.get(veh)
        if on is None or on[0] != tr.trip:
            came = on[2] if on is not None \
                and self.net.trip_next.get(on[0]) == tr.trip else None
            sched = clock(tr.sched[0], tr.ts, self.tz)
            self._out[veh] = sched, came is not None and came + TURN < sched
            on = self._on[veh] = [tr.trip, False, None]
        if tr.s < tr.sdist[-1] - AT_END:
            on[1] = True
        elif on[1] and on[2] is None:
            on[2] = tr.ts
        out = self._out.get(veh)
        if out is not None and AWAY <= tr.s - tr.sdist[0] <= STRAY:
            del self._out[veh]
            self.left(self._key(tr.trip), tr.trip, tr.ts, *out)

    def _key(self, trip):
        return self.net.trip_route[trip], self.net.trip_stops[trip][0][0]

    def left(self, key, trip, dep, sched, early):
        """`trip` set off from its first stop at `dep`."""
        self.last[key] = dep, sched
        if early:
            self.see(key, dep - sched > -WAITED, sched - dep)
        for t, f in self._asked.pop(trip, ()):
            self._add((*f, dep - t))
        for k in [k for k, got in self._asked.items() if got[-1][0] < dep - PENDING]:
            del self._asked[k]

    def see(self, key, waited, ahead):
        got = self.seen.get(key)
        if got is None:
            got = self.seen[key] = collections.deque(maxlen=KEEP)
        got.append((bool(waited), float(ahead)))

    def came(self, veh, trip):
        """When this vehicle got to the end of `trip`, if it is in."""
        on = self._on.get(veh)
        return on[2] if on is not None and on[0] == trip else None

    def stand(self, trip, sched, ready, now):
        """A vehicle in at `ready` stands to leave on `trip`, which the
        timetable has leave at `sched`: this minute is noted to learn from,
        and timed with the epoch's others by `foretell`."""
        if ready + TURN >= sched:
            return
        soonest = max(now, ready + TURN)
        key = self._key(trip)
        got = self.seen.get(key, ())
        habit = self._habit(got, sched, soonest, now) or (max(sched, soonest),) * 2
        f = self._features(key, got, sched, ready, now, habit)
        self._asked.setdefault(trip, []).append((now, f))
        self._batch.append((trip, soonest, f))

    def stand_after(self, trip, ready, now, running):
        """A vehicle in at the end of `trip` since `ready` stands for the trip
        it runs next, unless that one is already `running`."""
        trip = self.net.trip_next.get(trip)
        if trip is not None and trip not in running:
            sched = clock(self.net.trip_stops[trip][2][0], now, self.tz)
            self.stand(trip, sched, ready, now)

    def foretell(self, now):
        """Time this epoch's stands in one go - a model's call costs ~5 ms
        however few rows it is given."""
        batch, self._batch = self._batch, []
        self._foretold = {}
        if self.model is None or not batch:
            return
        left = self.model.predict(np.array([f for *_, f in batch]))
        self._foretold = {trip: max(soonest, now + float(dt))
                          for (trip, soonest, _), dt in zip(batch, left)}

    def leave(self, trip, sched, ready, now):
        """When a vehicle in at `ready` - or due in then - sets off on `trip`,
        which the timetable has leave at `sched`, as seen at `now`: as
        `foretell` has it if it stands there, otherwise by the rule."""
        if trip in self._foretold:
            return self._foretold[trip]
        soonest = max(now, ready + TURN)
        kept = max(sched, soonest)
        if ready + TURN >= sched:
            return kept
        habit = self._habit(self.seen.get(self._key(trip), ()), sched, soonest, now)
        return kept if habit is None else sum(habit) / 2

    @staticmethod
    def _habit(got, sched, soonest, now):
        """As far ahead of the timetable as the route's early departures that
        are still to come went, and as far as the last one went - or None
        where the route keeps the timetable. Only the departures that left
        after `now` count for the first: a vehicle still in after nearly all
        of them is waiting for the timetable after all."""
        if len(got) < NEED or np.mean([w for w, _ in got]) >= WAITS:
            return None
        kept = max(sched, soonest)
        ahead = [a for w, a in got if not w and sched - a > now]
        habit = kept if len(ahead) < STILL else max(
            soonest, sched - float(np.quantile(ahead, QUANTILE)))
        return habit, max(soonest, sched - got[-1][1])

    def _features(self, key, got, sched, ready, now, habit):
        """This minute of a stand as a row of `FEATURES`, missing as nan."""
        ahead = [a for w, a in got if not w]
        qs = np.quantile(ahead, (0.25, 0.5, 0.75)) if ahead else (np.nan,) * 3
        dep, was = self.last.get(key, (np.nan, np.nan))
        after = habit[0] if np.isnan(dep) else max(now, ready + TURN, dep + sched - was)
        local = datetime.datetime.fromtimestamp(now, self.tz)
        return (now - ready, sched - now, sched - ready,
                np.mean([w for w, _ in got]) if got else np.nan, len(got), *qs,
                now - dep, sched - was, was - dep, habit[0] - now, after - now,
                habit[1] - now, local.hour + local.minute / 60)

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

    def _add(self, row):
        self._rows[self._wrote % ROWS] = row
        self._wrote += 1

    def training(self):
        """A copy of the rows to `fit` on, oldest first: `FEATURES` and the
        seconds that were left."""
        if self._wrote < ROWS:
            return self._rows[:self._wrote].copy()
        at = self._wrote % ROWS
        return np.concatenate([self._rows[at:], self._rows[:at]])

    def restore_rows(self, rows):
        """Rows from `training`, if they are of this version's `FEATURES`, taken
        as older than any this one has written itself."""
        if rows.ndim == 2 and rows.shape[1] == self._rows.shape[1]:
            rows = np.concatenate([rows, self.training()])[-ROWS:]
            self._rows[:len(rows)] = rows
            self._wrote = len(rows)


def fit(rows):
    """A model of the seconds left to a departure, learned from `training`
    rows; None while there are too few."""
    if len(rows) < NEED_ROWS:
        return None
    pick = np.random.default_rng(0).choice(len(rows), min(FIT_ROWS, len(rows)),
                                           replace=False)
    model = HistGradientBoostingRegressor(loss="quantile", quantile=LEAN,
                                          max_iter=ITERS, learning_rate=RATE,
                                          random_state=0)
    return model.fit(rows[pick, :-1], rows[pick, -1])


def clock(sched, now, tz):
    """A timetable time - seconds past a service day's midnight, possibly
    over 24 h - as the unix instant nearest `now`."""
    local = datetime.datetime.fromtimestamp(now, tz)
    midnight = local.replace(hour=0, minute=0, second=0,
                             microsecond=0).timestamp()
    return min((midnight + k * DAY + sched for k in (-1, 0, 1)),
               key=lambda t: abs(t - now))
