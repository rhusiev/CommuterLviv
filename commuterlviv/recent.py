"""What the last minutes say that the pace model does not: how far the city's
recent arrivals came off what was foretold of them, how fast a vehicle itself
has been going, and how far the vehicles ahead of and behind it are.

`Boost` notes every epoch's ETAs here (`note`) and the stops passed
(`passed`), and asks each vehicle's `features` to correct and to learn with.
"""
import bisect
from collections import defaultdict, deque

import numpy as np

AHEAD_S = 900.0    # a stop's first forecast this many s out or less is kept to learn the miss from
MIN_AHEAD_S = 60.0  # nor fewer: a stop a minute away is passed on time by any model
RECENT_S = 1800.0  # s of passed stops the city's recent miss is a median of
OWN_S = 300.0      # s of a vehicle's own run its recent speed is taken over
MIN_OWN_S = 60.0   # nor fewer: two fixes close together give no speed
PENDING_S = 2 * 3600.0  # s a forecast waits for its stop to be passed before dropped
NAMES = ("city miss", "city misses", "own speed", "own pace", "m to leader",
         "s to leader", "leader fix age", "m to follower")


class Recent:
    """The recent past of each run and of the city, kept from epoch to epoch."""

    def __init__(self, max_gap_s):
        self.max_gap_s = max_gap_s
        self._went = defaultdict(deque)   # (veh, trip, run) -> (time, metres along)
        self._told = {}       # (veh, trip, run, stop index) -> (time, s foretold)
        self._last = {}       # (veh, trip, run) -> the furthest stop index told
        self._missed = deque()            # (time passed, log of real / foretold s)
        self._city = (np.nan, 0)
        self._lines = {}      # shape -> sorted [(metres along, veh, fix time)]

    def note(self, now, got):
        """Note where each `(veh, track, (next stop, metres along, seconds,
        inside the horizon))` of `got` is at `now`, and the first forecast of
        each stop it comes to `AHEAD_S` of."""
        lines = defaultdict(list)
        for veh, tr, (i, s_now, dt, _) in got:
            run = veh, tr.trip, tr.run
            went = self._went[run]
            went.append((now, s_now))
            while went[0][0] < now - 2 * OWN_S:
                went.popleft()
            near = i + int(np.searchsorted(dt, AHEAD_S, side="right"))
            for j in range(max(i, self._last.get(run, -1) + 1), near):
                self._told[(*run, j)] = now, float(dt[j - i])
            self._last[run] = max(self._last.get(run, -1), near - 1)
            lines[tr.shape_id].append((s_now, veh, tr.ts))
        for line in lines.values():
            line.sort()
        self._lines = lines
        self._forget(now)

    def _forget(self, now):
        while self._missed and self._missed[0][0] < now - RECENT_S:
            self._missed.popleft()
        self._city = ((float(np.median([m for _, m in self._missed])), len(self._missed))
                      if self._missed else (np.nan, 0))
        for key in [key for key, (t, _) in self._told.items() if t < now - PENDING_S]:
            del self._told[key]
        for run in [run for run, went in self._went.items() if went[-1][0] < now - PENDING_S]:
            del self._went[run]
            self._last.pop(run, None)

    def passed(self, veh, tr, j, t, gap):
        """`veh` on `tr` passed its stop `j` at `t`, timed between fixes `gap`
        s apart: how far that came off its first forecast."""
        told = self._told.pop((veh, tr.trip, tr.run, j), None)
        if told is None or gap > self.max_gap_s:
            return
        at, dt = told
        if dt >= MIN_AHEAD_S and t > at:
            self._missed.append((t, float(np.log((t - at) / dt))))

    def features(self, veh, tr, now, s_now, time_between):
        """`NAMES` for `veh` on `tr` at `s_now` metres, NaN where unknown;
        `time_between` is the pace model's."""
        own_m = own_s = np.nan
        went = self._went.get((veh, tr.trip, tr.run), ())
        then = next(((t, s) for t, s in went if t >= now - OWN_S - 1), None)
        if then is not None and then[0] < now - MIN_OWN_S:
            own_m = (s_now - then[1]) / (now - then[0])
            if own_m > 0:
                own_s = float(time_between(tr.shape_id, then[1], s_now)) / (now - then[0])
        lead_m = lead_s = lead_age = foll_m = np.nan
        line = self._lines.get(tr.shape_id, [])
        n = bisect.bisect_left(line, (s_now, veh, tr.ts))
        if n + 1 < len(line):
            lead, _, lead_ts = line[n + 1]
            lead_m = lead - s_now
            lead_s = float(time_between(tr.shape_id, s_now, lead))
            lead_age = now - lead_ts
        if n > 0:
            foll_m = s_now - line[n - 1][0]
        return (*self._city, own_m, own_s, lead_m, lead_s, lead_age, foll_m)
