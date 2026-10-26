"""The tracked vehicles as trips of their own, and how far the timetable is
believed on a route none is seen on."""
import math

import numpy as np

from .. import replay
from .timetable import _seconds_since_midnight


# s before the forecast horizon within which a vehicle's last prediction counts
# as cut off by it rather than as the end of its line
HORIZON_EDGE = 300.0

# a route the schedule wanted QUIET_TRIPS times inside QUIET_WINDOW seconds,
# with nothing tracked on it since, is taken to not be running
QUIET_WINDOW = 3600.0
QUIET_TRIPS = 2


class LiveTrip:
    """One tracked vehicle dressed as a single-trip pattern; its times are
    absolute unix seconds, not seconds since midnight. From `turns` on it runs
    the trips after the one it is on (`Live._next_trips`)."""

    __slots__ = ("route", "veh", "stops", "times", "turns")

    def __init__(self, route, veh, stops, times, turns=math.inf):
        self.route = route
        self.veh = veh
        self.stops = np.asarray(stops, dtype=np.int32)
        self.times = np.asarray(times, dtype=np.float64)
        self.turns = turns


def live_trips(tt, arrivals, catalog, now, horizon=replay.HORIZON):
    """Every tracked vehicle as a one-trip pattern, plus the last time one calls
    at each (stop, route) pair. Scheduled departures up to then are the ones
    those vehicles are running, so the caller should suppress them."""
    trips, covered = [], {}
    if arrivals is None or not len(arrivals.eta):
        return trips, covered
    for veh in np.unique(arrivals.eta["veh"]):
        rows = arrivals.of(int(veh))
        stops, times, turns = [], [], math.inf
        for r in rows:
            when = float(r["t"])
            if when < now or when > now + horizon:
                continue
            sid = catalog.stops[int(r["stop"])]
            i = tt.stop_i.get(sid)
            if i is None:
                continue
            stops.append(i)
            times.append(when)
            if r["planned"]:
                turns = min(turns, when)
        if len(stops) < 2:
            continue
        route = catalog.routes[int(rows[0]["route"])]
        if times[-1] > now + horizon - HORIZON_EDGE:
            _run_on(tt, route, stops, times)
        for i, when in zip(stops, times):
            covered[(i, route)] = max(covered.get((i, route), -math.inf), when)
        trips.append(LiveTrip(route, int(veh), stops, times, turns))
    return trips, covered


def _run_on(tt, route, stops, times):
    """Carries a vehicle cut off by the forecast horizon on to the end of its
    line, at the timetable's running times from its last predicted stop."""
    a, b = stops[-2], stops[-1]
    for pat in tt.by_route.get(route, ()):
        hit = np.flatnonzero((pat.stops[:-1] == a) & (pat.stops[1:] == b))
        # a pattern runs no trips on a day none of its services does
        if not len(hit) or not len(pat.times):
            continue
        j = int(hit[0]) + 1
        _, midnight = _seconds_since_midnight(times[-1])
        col = pat.times[:, j]
        row = pat.times[int(np.argmin(np.abs(col - (times[-1] - midnight))))]
        stops.extend(int(s) for s in pat.stops[j + 1:])
        times.extend(times[-1] + row[j + 1:] - row[j])
        return


def route_confidence(tt, live, sod, window=QUIET_WINDOW, expected=QUIET_TRIPS):
    """How much a scheduled departure on each route is worth believing.

    A route with a vehicle being tracked is "live". One with none is "quiet"
    when the schedule wanted at least `expected` trips out of it in the last
    `window` seconds and not one of them turned up, which is what a line nobody
    is running looks like from here; otherwise it is "schedule", because a route
    that runs twice an hour is silent between runs by design.
    """
    running = {trip.route for trip in live}
    due = {}
    for pat in tt.patterns:
        if pat.route in running:
            continue
        col = pat.times[:, 0]
        due[pat.route] = due.get(pat.route, 0) + int(
            np.count_nonzero((col >= sod - window) & (col <= sod)))
    return {route: "quiet" if n >= expected else "schedule"
            for route, n in due.items()}
