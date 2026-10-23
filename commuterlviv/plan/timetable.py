"""The scheduled city as trips grouped into patterns, and the day of it a
search runs on."""
import copy
import datetime
import functools

import numpy as np

from .. import localtime


class Pattern:
    """Every trip that calls at the same stops in the same order.

    `times` is one row per trip, one column per stop, in seconds since the
    service day's midnight, rows sorted by departure. `service` indexes each
    row's service into `Timetable.services`; a pattern of a single day
    (`Timetable.on`) has none.
    """

    __slots__ = ("route", "stops", "times", "service")

    def __init__(self, route, stops, times, service=None):
        self.route = route
        self.stops = np.asarray(stops, dtype=np.int32)
        self.times = np.asarray(times, dtype=np.float64)
        self.service = service

    def running(self, runs):
        """The trips running on the day before, the day and the day after -
        `runs` holding each day's services - as one day's pattern in seconds
        since its midnight. The day before's count only past that midnight."""
        day = localtime.DAY_S
        before = self.times[runs[0][self.service]]
        times = np.concatenate((before[before[:, -1] >= day] - day,
                                self.times[runs[1][self.service]],
                                self.times[runs[2][self.service]] + day))
        return Pattern(self.route, self.stops,
                       times[np.argsort(times[:, 0], kind="stable")])


class Timetable:
    """The scheduled city, as trips grouped into patterns.

    Stops are indexed by `sorted(net.stops)` and `stop_i` maps a feed id into
    that; the live side keys by the catalog's order instead, so callers must
    translate.

    It holds every trip of every service; a search reads the one day it runs
    on, from `on`. The services and their calendar are the network's, never
    the feed on disk, which may have been fetched again since the network was
    built from it.
    """

    VERSION = 4

    def __init__(self, net):
        self.version = self.VERSION
        self.net = net
        self.stops = sorted(net.stops)
        self.stop_i = {s: i for i, s in enumerate(self.stops)}
        self.calendar = net.calendar
        of = net.trip_service
        self.services = sorted(set(of.values()))
        service_i = {s: i for i, s in enumerate(self.services)}
        by_key = {}
        for trip, (stops, _, sched) in net.trip_stops.items():
            route = net.trip_route.get(trip)
            if route is None or len(stops) < 2 or trip not in of:
                continue
            key = (route, tuple(stops))
            by_key.setdefault(key, []).append((sched, service_i[of[trip]]))
        self.patterns = []
        for (route, stops), rows in by_key.items():
            times = np.array([r[0] for r in rows], dtype=np.float64)
            order = np.argsort(times[:, 0], kind="stable")
            idx = [self.stop_i[s] for s in stops]
            self.patterns.append(Pattern(
                route, idx, times[order],
                np.array([r[1] for r in rows], dtype=np.int32)[order]))

    def on(self, midnight):
        """The timetable as it runs on the day starting at `midnight`, unix
        seconds; see `Pattern.running`."""
        return _day(self, midnight)

    @functools.cached_property
    def by_route(self):
        out = {}
        for pat in self.patterns:
            out.setdefault(pat.route, []).append(pat)
        return out

    @property
    def lat(self):
        return np.array([self.net.stops[s]["lat"] for s in self.stops])

    @property
    def lon(self):
        return np.array([self.net.stops[s]["lon"] for s in self.stops])


@functools.lru_cache(maxsize=3)
def _day(tt, midnight):
    day = datetime.datetime.fromtimestamp(midnight, localtime.TZ).date()
    runs = [np.array([tt.calendar.runs(s, day + datetime.timedelta(days=d))
                      for s in tt.services], dtype=bool) for d in (-1, 0, 1)]
    out = copy.copy(tt)
    out.__dict__.pop("by_route", None)
    out.patterns = [pat.running(runs) for pat in tt.patterns]
    return out


def _seconds_since_midnight(now):
    midnight = localtime.midnight(now)
    return now - midnight, midnight
