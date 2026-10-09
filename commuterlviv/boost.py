"""A learned correction to the ETA model's seconds to each stop ahead.

The pace model (`model`) knows each stretch of road at each hour, but not the
habits of a route, of a day of the week or of a vehicle running late, and it
reads Lviv as faster than it is: over the recording of 2026-09-14 to 10-08 it
foretold arrivals 112 s early on average. A boosted model of its own misses
(`fit`), given what the model said with the timetable, the lateness, the
distance and stops to go, the hour, the weekday and what the last minutes
said (`recent`), learns those and takes the difference off. Within two minutes of a stop the model is better than the
correction, so there it is faded out (`FADE_FROM_S`). docs/service.md has
what it was measured on.
"""
import datetime

import numpy as np
from sklearn.ensemble import HistGradientBoostingRegressor

from . import recent

# the rows learned from: of the ETAs of an epoch every SAMPLE_S, a KEEP share,
# labelled when the vehicle passes the stop. Lviv has ~460 000 such ETAs a day
# with a timed passing, ~77 000 kept, so the ring holds about 6.5 days
SAMPLE_S = 600.0
KEEP = 0.15
ROWS = 500_000
NEED_ROWS = 20_000  # before a fitted model is trusted, ~6 h of service
MAX_GAP_S = 120.0   # s between the fixes a passing is timed between, at most
PENDING_S = 2 * 3600.0  # s an ETA waits for its stop to be passed before dropped
ITERS = 300
RATE = 0.08
LEAVES = 63
# rows a leaf holds at least, and the L2 penalty on its value: a fit on a few
# hours of rows is less sure of itself, and as good on a week's
MIN_LEAF = 200
L2 = 10.0
# below FADE_FROM_S the model is left alone, past FADE_FROM_S + FADE_S the
# correction is taken whole. Chosen from the test above, not derived
FADE_FROM_S = 60.0
FADE_S = 120.0
# the share of its seconds a corrected ETA is brought forward by. A median fit
# is as often early as late, but a rider told too late misses the vehicle: at
# 4% that happens as rarely as with the model alone. Chosen, not derived
EARLIER = 0.04
MIN_TIMETABLE_S = 30.0  # timetabled s to a stop below which their ratio to the model's is noise
FEATURES = ("model s", "timetable s", "late", "m to go", "stops to go", "speed",
            "fix age", "hour", "weekday", "route", "type", "stop", "stops",
            "model per timetable", *recent.NAMES)
CATEGORIES = ("route", "type")
TYPES = ("bus", "tram", "trolleybus")
DAY_S = 86400.0


class Boost:
    """The ETAs asked about, the stops passed, and the correction they teach."""

    def __init__(self, net, tz):
        self.net = net
        self.tz = tz
        self.routes = sorted(net.routes)   # what the "route" feature numbers
        self._route = {r: (i, TYPES.index(net.routes[r]["type"]))
                       for i, r in enumerate(self.routes)}
        self._rows = np.zeros((ROWS, len(FEATURES) + 1), dtype=np.float32)
        self._wrote = 0      # rows ever written; the ring keeps the last `ROWS`
        self.model = None
        self._asked = {}     # (veh, trip, run, stop index) -> [(time, features)]
        self._pick = np.random.default_rng(0)
        self._sampled = -np.inf   # when ETAs were last noted to learn from
        self.recent = recent.Recent(MAX_GAP_S)

    def correct(self, now, asked, time_between):
        """Correct in place, in one call of the model, the seconds `etas` gave
        each `(veh, track)` of `asked` - each a `(next stop, distance, seconds,
        inside the horizon)` or None - `time_between` being the pace model's.
        Note them in `recent`, and on a sampled epoch to learn from too."""
        got = [(veh, tr, e) for (veh, tr), e in asked if e is not None]
        self.recent.note(now, got)
        learn = now - self._sampled >= SAMPLE_S
        if not got or self.model is None and not learn:
            return
        rows = [self._features(veh, tr, now, time_between, *e) for veh, tr, e in got]
        if learn:
            self._sampled = now
            self._note(now, got, rows)
        if self.model is None:
            return
        fix = self.model.predict(np.concatenate(rows))
        at = 0
        for _, _, (_, _, dt, k) in got:
            w = np.clip((dt[k] - FADE_FROM_S) / FADE_S, 0.0, 1.0)
            fixed = dt[k] + w * fix[at:at + len(k)]
            dt[k] = fixed - w * EARLIER * np.maximum(fixed, 0.0)
            np.maximum.accumulate(np.maximum(dt, 0.0), out=dt)
            at += len(k)

    def _features(self, veh, tr, now, time_between, i, s_now, dt, k):
        """One row of `FEATURES` per stop inside the horizon."""
        j = i + k
        sched_now = float(np.interp(s_now, tr.sdist, tr.sched))
        sched = tr.sched[j] - sched_now
        per = np.full(len(k), np.nan)
        np.divide(dt[k], sched, out=per, where=sched > MIN_TIMETABLE_S)
        local = datetime.datetime.fromtimestamp(now, self.tz)
        day_s = local.hour * 3600 + local.minute * 60 + local.second
        late = (day_s - sched_now + DAY_S / 2) % DAY_S - DAY_S / 2
        route, kind = self._route.get(self.net.trip_route.get(tr.trip), (np.nan,) * 2)
        same = (tr.v, now - tr.ts, local.hour + local.minute / 60, local.weekday(),
                route, kind)
        lately = self.recent.features(veh, tr, now, s_now, time_between)
        return np.column_stack([dt[k], sched, np.full(len(k), late),
                                tr.sdist[j] - s_now, k + 1,
                                *(np.full(len(k), v) for v in same), j,
                                np.full(len(k), len(tr.sdist)), per,
                                *(np.full(len(k), v) for v in lately)])

    def _note(self, now, got, rows):
        for (veh, tr, (i, _, _, k)), f in zip(got, rows):
            for n in np.nonzero(self._pick.random(len(k)) < KEEP)[0]:
                key = veh, tr.trip, tr.run, int(i + k[n])
                self._asked.setdefault(key, []).append((now, f[n]))
        for key in [key for key, a in self._asked.items() if a[-1][0] < now - PENDING_S]:
            del self._asked[key]

    def passed(self, veh, tr, j, t, gap):
        """`veh` on `tr` passed its stop `j` at `t`, timed between fixes `gap`
        s apart: what was foretold of it is labelled with how far out it was."""
        self.recent.passed(veh, tr, j, t, gap)
        asked = self._asked.pop((veh, tr.trip, tr.run, j), ())
        if gap > MAX_GAP_S:
            return
        for at, f in asked:
            self._rows[self._wrote % ROWS] = (*f, t - at - f[0])
            self._wrote += 1

    def training(self):
        """A copy of the rows to `fit` on, oldest first: `FEATURES` and how
        many seconds later than the model the stop was passed."""
        if self._wrote < ROWS:
            return self._rows[:self._wrote].copy()
        at = self._wrote % ROWS
        return np.concatenate([self._rows[at:], self._rows[:at]])

    def restore_rows(self, rows, routes):
        """Rows from `training`, if they are of this version's `FEATURES`, their
        "route" renumbered from `routes`, the `routes` they were noted under.
        They are taken as older than any this one has noted itself."""
        if rows.ndim == 2 and rows.shape[1] == self._rows.shape[1]:
            rows = rows[-ROWS:].copy()
            col = FEATURES.index("route")
            now = np.array([self._route.get(r, (np.nan,))[0] for r in routes] + [np.nan])
            was = np.nan_to_num(rows[:, col], nan=len(routes)).astype(np.int64)
            rows[:, col] = now[np.clip(was, 0, len(routes))]
            rows = np.concatenate([rows, self.training()])[-ROWS:]
            self._rows[:len(rows)] = rows
            self._wrote = len(rows)


def fit(rows):
    """A model of the model's miss, learned from `training` rows; None while
    there are too few."""
    if len(rows) < NEED_ROWS:
        return None
    model = HistGradientBoostingRegressor(
        loss="absolute_error", max_iter=ITERS, learning_rate=RATE,
        max_leaf_nodes=LEAVES, min_samples_leaf=MIN_LEAF, l2_regularization=L2,
        categorical_features=[f in CATEGORIES for f in FEATURES],
        random_state=0)
    return model.fit(rows[:, :-1], rows[:, -1])
