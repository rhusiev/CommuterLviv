"""A small made-up city for the tests: one bus line out along a straight road
and back, as a GTFS feed the real network build reads, and vehicles driving it.

The road runs east from near the city centre, `STOPS` stops `GAP_M` metres apart.
One block chains its trips out, back and out again; a fleet of unchained trips
runs out every `HEADWAY_S` seconds after it. The timetable has a bus take `LEG_S`
seconds between stops, which is how fast `drive` drives unless told otherwise,
so a model knowing only the timetable is right until it is.
"""
import csv
import datetime
import io
import sqlite3
import time
import zipfile
from dataclasses import dataclass

import numpy as np
from google.transit import gtfs_realtime_pb2 as rt

from commuterlviv import collect, gtfs, model, network, overrides

DAY = datetime.datetime(2026, 10, 5, tzinfo=model.TZ)   # a Monday
STOPS = 5
GAP_M = 500.0              # m between stops
LEG_S = 100.0              # s the timetable gives a leg, so 5 m/s
SPEED = GAP_M / LEG_S
LAT, LON = 49.84, 24.00
ROUTE = "r1"
# (trip, shape, first departure, s past midnight); each trip runs the whole line
TRIPS = (("t1", "out", 8 * 3600), ("t2", "back", 8 * 3600 + 1200),
         ("t3", "out", 8 * 3600 + 2400))
BLOCK = "b1"
HEADWAY_S = 300
FLEET_SIZE = 12
FLEET = tuple((f"f{k}", "out", 9 * 3600 + k * HEADWAY_S) for k in range(FLEET_SIZE))
FLEET_IDS = frozenset(trip for trip, *_ in FLEET)
SHAPE_OF = {trip: sid for trip, sid, _ in TRIPS + FLEET}
DEPARTS = {trip: dep for trip, _, dep in TRIPS + FLEET}
LENGTH = GAP_M * (STOPS - 1)
STEPS = 400              # pieces `drive` integrates a speed over


def at(sched):
    """A timetable time on `DAY` as a unix instant."""
    return DAY.timestamp() + sched


def _point(d):
    """Latitude and longitude `d` metres east of the start."""
    return LAT, LON + d / network.KX


def _hms(s):
    return f"{int(s) // 3600:02d}:{int(s) % 3600 // 60:02d}:{int(s) % 60:02d}"


def _table(rows):
    out = io.StringIO()
    w = csv.DictWriter(out, fieldnames=list(rows[0]))
    w.writeheader()
    w.writerows(rows)
    return out.getvalue()


def feed():
    """The city as the bytes of a static GTFS zip."""
    ends = {"out": (0.0, LENGTH), "back": (LENGTH, 0.0)}
    shapes = [{"shape_id": sid, "shape_pt_sequence": i,
               "shape_pt_lat": f"{_point(d)[0]:.7f}",
               "shape_pt_lon": f"{_point(d)[1]:.7f}"}
              for sid, (a, b) in ends.items()
              for i, d in enumerate(np.linspace(a, b, 2 * STOPS - 1))]
    stops = [{"stop_id": f"s{i}", "stop_code": str(100 + i), "stop_name": f"Stop {i}",
              "stop_desc": "", "stop_lat": f"{_point(i * GAP_M)[0]:.7f}",
              "stop_lon": f"{_point(i * GAP_M)[1]:.7f}"} for i in range(STOPS)]
    trips, times = [], []
    for trip, sid, dep in TRIPS + FLEET:
        trips.append({"route_id": ROUTE, "service_id": "all", "trip_id": trip,
                      "direction_id": 0 if sid == "out" else 1, "shape_id": sid,
                      "block_id": "" if trip in FLEET_IDS else BLOCK})
        order = range(STOPS) if sid == "out" else range(STOPS - 1, -1, -1)
        for seq, i in enumerate(order):
            t = _hms(dep + seq * LEG_S)
            times.append({"trip_id": trip, "arrival_time": t, "departure_time": t,
                          "stop_id": f"s{i}", "stop_sequence": seq})
    tables = {
        "routes.txt": [{"route_id": ROUTE, "route_short_name": "А1",
                        "route_long_name": "Stop 0 - Stop 4", "route_type": 3}],
        "stops.txt": stops,
        "shapes.txt": shapes,
        "trips.txt": trips,
        "stop_times.txt": times,
        "calendar.txt": [{"service_id": "all", "monday": 1, "tuesday": 1,
                          "wednesday": 1, "thursday": 1, "friday": 1,
                          "saturday": 1, "sunday": 1, "start_date": "20260101",
                          "end_date": "20261231"}],
    }
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w") as z:
        for name, rows in tables.items():
            z.writestr(name, _table(rows))
    return out.getvalue()


def install(monkeypatch, data):
    """Point the package at a data directory holding only this city's feed,
    and its network cache, so nothing touches the real ones; the city's
    network, built from that feed."""
    data.mkdir(exist_ok=True)
    zip_path = data / "static.zip"
    zip_path.write_bytes(feed())
    monkeypatch.setattr(gtfs, "DATA", data)
    monkeypatch.setattr(gtfs, "ZIP", zip_path)
    monkeypatch.setattr(network, "CACHE", str(data / "network.pkl"))
    monkeypatch.setattr(overrides.Overrides, "load", classmethod(lambda cls: cls([])))
    return network.build()


@dataclass(frozen=True)
class Fix:
    """One vehicle position, as the feed reports it."""
    trip: str
    ts: float
    lat: float
    lon: float
    speed: float        # m/s
    odometer: float     # km, as the feed reports it


def drive(trip, start, every=10.0, stand=0.0, odometer=0.0, speed=None):
    """A vehicle on `trip`, leaving its first stop at `start` and driving at
    `speed(distance driven)` m/s - `SPEED` throughout unless given - without
    stopping, then standing `stand` s at the far end. One fix every `every` s,
    from the departure on."""
    speed = speed or (lambda d: np.full_like(d, SPEED))
    xs = np.linspace(0.0, LENGTH, STEPS + 1)
    times = start + np.concatenate([[0.0], np.cumsum(
        np.diff(xs) / speed((xs[1:] + xs[:-1]) / 2))])
    fixes = []
    for t in np.arange(start, times[-1] + stand + every / 2, every):
        run = float(np.interp(t, times, xs))
        d = run if SHAPE_OF[trip] == "out" else LENGTH - run
        lat, lon = _point(d)
        v = float(speed(np.array(run))) if run < LENGTH else 0.0
        fixes.append(Fix(trip, float(t), lat, lon, v, odometer + run / 1000.0))
    return fixes


def jammed(d):
    """A speed for `drive`: the far half of the road four times as slow as the
    timetable says."""
    return np.where(d < LENGTH / 2, SPEED, SPEED / 4)


def ride(trip, **kw):
    """`drive` the trip from its timetabled departure."""
    return drive(trip, at(DEPARTS[trip]), **kw)


def record(path, vehicles, delay=2.0):
    """A recording as the collector writes it: each vehicle's fixes, polled
    `delay` s after they were taken."""
    con = sqlite3.connect(path)
    con.executescript(collect.SCHEMA)
    con.executemany(
        "INSERT INTO veh(veh_id, veh_ts, route_id, trip_id, lat, lon, speed,"
        " odometer, poll_ts) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [(veh, int(f.ts), ROUTE, f.trip, f.lat, f.lon, f.speed, f.odometer,
          f.ts + delay) for veh, fixes in vehicles.items() for f in fixes])
    con.commit()
    con.close()


class Feed:
    """The vehicle-position feed: one bus out along the line, over and over,
    as if it had left the first stop when the feed was made. Stands in for
    `collect.rt`."""

    def __init__(self):
        self.start = time.time()
        self.lap = drive("t1", 0.0, every=1.0)    # a fix per second of the ride

    def __call__(self, endpoint, tries=3):
        assert endpoint == "vehicle_position"
        now = time.time()
        fix = self.lap[int(now - self.start) % len(self.lap)]
        msg = rt.FeedMessage()
        msg.header.gtfs_realtime_version = "2.0"
        msg.header.timestamp = int(now)
        v = msg.entity.add(id="1").vehicle
        v.vehicle.id = "bus-1"
        v.trip.trip_id = fix.trip
        v.timestamp = int(now)
        v.position.latitude, v.position.longitude = fix.lat, fix.lon
        v.position.speed, v.position.odometer = fix.speed, fix.odometer
        return msg
