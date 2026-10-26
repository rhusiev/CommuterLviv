"""Stops the feed lists on a route that its vehicles drive past.

The feed has no pickup or drop-off columns, so a stop a route never calls at
looks like any other, and the rider waits there for a bus that will not stop
(А16 and А53 northbound at Колодзінського, 0800, reported 2026-10). The
recording is the only witness: a vehicle that calls at a stop stands near it,
slow, on most trips. For every pattern `check` counts the trips that stood at
each of its stops and flags the stops far fewer stood at than at the
pattern's usual one.

It only reports. Taking a stop off a route is a person's call, made with a
`[[remove]]` rule in `overrides.toml`; the network is built with those rules,
so a stop already removed from a route is not on its patterns to be checked,
while the other routes through it still are.

    python -m commuterlviv skipped [--db data/feed.db] [--days 7]
"""
import argparse
import contextlib
import sqlite3
import statistics
import time
from dataclasses import dataclass

import numpy as np
from scipy.spatial import cKDTree

from . import network, replay
from .localtime import DAY_S

# Chosen from the recording of 2026-09-16..23: at 20 m, 391 stops fell under
# `SKIP_SHARE`, and 255 of them had 20 slow fixes within 60 m - vehicles that
# call there but stand off the pole. At 40 m 225 did, and А16 and А53 still
# stood at 0800 on under 1% of their trips. A fix counts only for its nearest
# stop of the pattern, so close stops of one pattern do not share fixes.
RADIUS_M = 40.0
# Chosen: under the tracker's 0.7 m/s standing threshold, so a bus crawling
# past in a queue mostly does not count as calling.
SLOW_MPS = 0.5
# A week covers every weekday's timetable once and, at the tens of trips a day
# a route runs, gives the usual stop hundreds of trips to compare with; it
# reads about a quarter of the slow fixes a month would.
WINDOW_S = 7 * DAY_S
# Chosen: under this many trips standing at the pattern's usual stop, too few
# of its trips were seen to say anything about the others.
MIN_TRIPS = 30
# Chosen from the same week at 40 m: of 3268 stops on 130 patterns 180 lay
# under 0.05 of the usual count, then 45, 26 and 19 per 0.05 up to 0.2 - the
# trough - and every route's 0800 northbound under 0.06. 801 southbound, where
# buses partly stand 20-40 m off the pole, lay at 0.13-0.14 and is not flagged
SKIP_SHARE = 0.1


@dataclass(frozen=True)
class Skipped:
    """A listed stop the pattern's vehicles seldom stood at."""
    route: str       # the short name, as in `overrides.toml`
    toward: str      # the name of the pattern's last stop
    stop: str        # feed id
    code: str        # as on the sign, and as `overrides.toml` names it
    name: str
    trips: int       # trips that stood within `RADIUS_M`, slower than `SLOW_MPS`
    usual: int       # the same, at the median stop of the pattern
    fixes: int       # standing fixes near it, all trips together

    def line(self):
        return (f"{self.route} toward {self.toward}: stop {self.code} "
                f"{self.name} - {self.trips} trips stood there against "
                f"{self.usual} at its usual stop ({self.fixes} fixes)")


def check(net, db=None, until=None, window_s=WINDOW_S):
    """Every pattern's listed stops its vehicles stood at under `SKIP_SHARE`
    as often as at its usual stop, over the `window_s` s of the recording `db`
    up to `until`, most skipped first. Blocking; run it in a thread."""
    db = db or replay.DB
    until = time.time() if until is None else until
    patterns, of = _patterns(net)
    by = {}
    for trip, ts, lat, lon in _slow(db, until - window_s, until):
        k = of.get(trip)
        if k is not None:
            by.setdefault(k, []).append((trip, ts, lat, lon))
    out = []
    for k, rows in by.items():
        out += _judge(net, *patterns[k], rows)
    return sorted(out, key=lambda s: (s.trips / s.usual, -s.usual))


def _patterns(net):
    """Each (route, stops) the trips run, and which one each trip runs."""
    index, patterns, of = {}, [], {}
    for trip, (ids, _, _) in net.trip_stops.items():
        key = (net.trip_route.get(trip), ids)
        if key not in index:
            index[key] = len(patterns)
            patterns.append(key)
        of[trip] = index[key]
    return patterns, of


def _slow(db, t_from, t_to):
    """The recording's slow on-trip fixes between `t_from` and `t_to`; the
    `veh_ts` index bounds the read to the window."""
    sql = ("SELECT trip_id, veh_ts, lat, lon FROM veh WHERE veh_ts >= ? "
           "AND veh_ts < ? AND speed < ? AND trip_id IS NOT NULL")
    with contextlib.closing(sqlite3.connect(f"file:{db}?mode=ro", uri=True)) as con:
        yield from con.execute(sql, (t_from, t_to, SLOW_MPS))


def _judge(net, route, ids, rows):
    """The pattern's stops that too few of its trips stood at.

    The ends are left out: a vehicle takes its next trip's id only once it
    leaves the first stop, and often stands away from the last one's pole, so
    neither is seen as a call there.
    """
    stops = sorted(set(ids[1:-1]))
    if not stops:
        return []
    tree = cKDTree(network.to_xy(np.array([net.stops[s]["lat"] for s in stops]),
                                 np.array([net.stops[s]["lon"] for s in stops])))
    trip, ts, lat, lon = zip(*rows)
    _, near = tree.query(network.to_xy(np.array(lat), np.array(lon)),
                         distance_upper_bound=RADIUS_M)
    runs = {s: set() for s in range(len(stops))}
    fixes = dict.fromkeys(runs, 0)
    for t, day, s in zip(trip, np.array(ts) // DAY_S, near):
        # a UTC day splits no trip: it turns at 02:00 or 03:00 in Kyiv, when
        # nothing runs
        if s < len(stops):
            runs[s].add((t, day))
            fixes[s] += 1
    usual = statistics.median(len(r) for r in runs.values())
    if usual < MIN_TRIPS:
        return []
    short = net.routes.get(route, {}).get("short", route)
    toward = net.stops[ids[-1]]["name"]
    return [Skipped(short, toward, stops[s], net.stops[stops[s]]["code"],
                    net.stops[stops[s]]["name"], len(r), int(usual), fixes[s])
            for s, r in runs.items() if len(r) < SKIP_SHARE * usual]


def main(argv):
    ap = argparse.ArgumentParser(prog="commuterlviv skipped",
                                 description=__doc__.split("\n\n")[0])
    ap.add_argument("--db", default=None, help="the recording, read only; "
                    "data/feed.db by default")
    ap.add_argument("--days", type=float, default=WINDOW_S / DAY_S,
                    help="how many days of the recording to read, back from --until")
    ap.add_argument("--until", type=float, default=None,
                    help="unix time the window ends at; now by default")
    a = ap.parse_args(argv)
    found = check(network.load(), a.db, a.until, a.days * DAY_S)
    for s in found:
        print(s.line())
    print(f"{len(found)} listed stop(s) the vehicles seldom stood at")
