#!/usr/bin/env python3
"""Continuously record the three Lviv feeds into SQLite.

  vehicle_position -> veh    (deduped on the GPS fix timestamp)
  trip_updates     -> pred   (stored only when a prediction changes)
  api.lad.lviv.ua  -> lad    (a rotating sample of stops)

Rows are only ever appended, so the evaluator can replay any past moment.
"""
import argparse
import collections
import datetime
import os
import queue
import sqlite3
import sys
import threading
import time

import requests
from google.transit import gtfs_realtime_pb2

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from .gtfs import BASE, DATA, table

DB = os.path.join(DATA, "feed.db")

SCHEMA = """
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;

CREATE TABLE IF NOT EXISTS poll(
  ts REAL, feed TEXT, header_ts INTEGER, n INTEGER, ms INTEGER, err TEXT);

CREATE TABLE IF NOT EXISTS veh(
  veh_id TEXT, veh_ts INTEGER, route_id TEXT, trip_id TEXT,
  lat REAL, lon REAL, bearing REAL, speed REAL, odometer REAL,
  poll_ts REAL, label TEXT,
  PRIMARY KEY(veh_id, veh_ts)) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS pred(
  poll_ts REAL, trip_id TEXT, veh_id TEXT, route_id TEXT,
  stop_id TEXT, stop_seq INTEGER, kind INTEGER, t INTEGER, start_date TEXT);
CREATE INDEX IF NOT EXISTS pred_key ON pred(trip_id, stop_id, poll_ts);
CREATE INDEX IF NOT EXISTS pred_ts ON pred(poll_ts);

CREATE TABLE IF NOT EXISTS lad(
  poll_ts REAL, stop_code TEXT, route TEXT, route_id TEXT,
  veh_id TEXT, scheduled INTEGER, arr INTEGER, end_stop TEXT, dir INTEGER);
CREATE INDEX IF NOT EXISTS lad_key ON lad(stop_code, poll_ts);
"""

stop_flag = threading.Event()
writes = queue.Queue()


def writer():
    db = sqlite3.connect(DB, timeout=60)
    db.executescript(SCHEMA)
    pending = collections.defaultdict(list)
    last = time.time()
    sql = {
        "poll": "INSERT INTO poll VALUES(?,?,?,?,?,?)",
        "veh": "INSERT OR IGNORE INTO veh VALUES(?,?,?,?,?,?,?,?,?,?,?)",
        "pred": "INSERT INTO pred VALUES(?,?,?,?,?,?,?,?,?)",
        "lad": "INSERT INTO lad VALUES(?,?,?,?,?,?,?,?,?)",
    }
    while True:
        try:
            item = writes.get(timeout=1.0)
            if item is None:
                break
            pending[item[0]].append(item[1])
        except queue.Empty:
            pass
        if time.time() - last > 2.0 and pending:
            for kind, rows in pending.items():
                db.executemany(sql[kind], rows)
            db.commit()
            pending.clear()
            last = time.time()
    for kind, rows in pending.items():
        db.executemany(sql[kind], rows)
    db.commit()
    db.close()


def log(*a):
    print(datetime.datetime.now().strftime("%H:%M:%S"), *a, flush=True)


def rt(endpoint, tries=3):
    for attempt in range(tries):
        try:
            body = requests.get(f"{BASE}/{endpoint}", timeout=30).content
            msg = gtfs_realtime_pb2.FeedMessage()
            msg.ParseFromString(body)
            return msg
        except Exception:
            if attempt == tries - 1:
                raise
            time.sleep(0.5)


def collect_vehicles(period):
    seen = {}
    while not stop_flag.is_set():
        t0 = time.time()
        try:
            msg = rt("vehicle_position")
            n = 0
            for e in msg.entity:
                v = e.vehicle
                key = v.vehicle.id
                if seen.get(key) == v.timestamp:
                    continue
                seen[key] = v.timestamp
                p = v.position
                writes.put(("veh", (
                    key, v.timestamp, v.trip.route_id or None, v.trip.trip_id or None,
                    p.latitude, p.longitude, p.bearing, p.speed, p.odometer,
                    t0, v.vehicle.label or None)))
                n += 1
            writes.put(("poll", (t0, "veh", msg.header.timestamp, n,
                                 int((time.time() - t0) * 1000), None)))
        except Exception as exc:
            writes.put(("poll", (t0, "veh", 0, 0, int((time.time() - t0) * 1000), repr(exc)[:200])))
            log("veh error", exc)
        stop_flag.wait(max(0.5, period - (time.time() - t0)))


def collect_trips(period):
    last = {}
    while not stop_flag.is_set():
        t0 = time.time()
        try:
            msg = rt("trip_updates")
            n = 0
            for e in msg.entity:
                tu = e.trip_update
                for stu in tu.stop_time_update:
                    kind = 0 if stu.HasField("arrival") else 1
                    t = stu.arrival.time if kind == 0 else stu.departure.time
                    if not t:
                        continue
                    key = (tu.trip.trip_id, stu.stop_id)
                    if last.get(key) == (kind, t):
                        continue
                    last[key] = (kind, t)
                    writes.put(("pred", (
                        t0, tu.trip.trip_id, tu.vehicle.id or None, tu.trip.route_id,
                        stu.stop_id, stu.stop_sequence, kind, t, tu.trip.start_date or None)))
                    n += 1
            writes.put(("poll", (t0, "pred", msg.header.timestamp, n,
                                 int((time.time() - t0) * 1000), None)))
        except Exception as exc:
            writes.put(("poll", (t0, "pred", 0, 0, int((time.time() - t0) * 1000), repr(exc)[:200])))
            log("pred error", exc)
        stop_flag.wait(max(0.5, period - (time.time() - t0)))


def lad_stop_codes(limit):
    counts = collections.Counter(r["stop_id"] for r in table("stop_times.txt"))
    stops = table("stops.txt")
    by_code = collections.Counter(s["stop_code"] for s in stops if s["stop_code"])
    ok = [s for s in stops
          if s["stop_code"].isdigit() and by_code[s["stop_code"]] == 1]
    ok.sort(key=lambda s: -counts.get(s["stop_id"], 0))
    return [(s["stop_code"].lstrip("0") or "0", s["stop_id"]) for s in ok[:limit]]


def collect_lad(period, limit):
    codes = lad_stop_codes(limit)
    log(f"lad sampling {len(codes)} stops")
    gap = period / max(1, len(codes))
    session = requests.Session()
    while not stop_flag.is_set():
        cycle = time.time()
        for code, _ in codes:
            if stop_flag.is_set():
                break
            t0 = time.time()
            try:
                r = session.get(f"https://api.lad.lviv.ua/stops/{code}", timeout=20)
                rows = r.json().get("timetable", []) if r.status_code == 200 else []
                for e in rows:
                    when = datetime.datetime.strptime(
                        e["arrival_time"], "%a, %d %b %Y %H:%M:%S %Z"
                    ).replace(tzinfo=datetime.timezone.utc)
                    writes.put(("lad", (
                        t0, code, e.get("route"), e.get("route_id"),
                        e.get("vehicle_id"), 1 if e.get("scheduled") else 0,
                        int(when.timestamp()), e.get("end_stop_name"),
                        e.get("direction_id"))))
                writes.put(("poll", (t0, "lad", 0, len(rows),
                                     int((time.time() - t0) * 1000),
                                     None if r.status_code == 200 else str(r.status_code))))
            except Exception as exc:
                writes.put(("poll", (t0, "lad", 0, 0, int((time.time() - t0) * 1000),
                                     repr(exc)[:200])))
            stop_flag.wait(max(0.05, gap - (time.time() - t0)))
        stop_flag.wait(max(0.5, period - (time.time() - cycle)))


def main(argv=None):
    ap = argparse.ArgumentParser(prog="lvivpred collect")
    ap.add_argument("--veh-period", type=float, default=5.0)
    ap.add_argument("--trip-period", type=float, default=15.0)
    ap.add_argument("--lad-period", type=float, default=60.0)
    ap.add_argument("--lad-stops", type=int, default=40)
    ap.add_argument("--hours", type=float, default=0)
    args = ap.parse_args(argv)

    os.makedirs(DATA, exist_ok=True)
    w = threading.Thread(target=writer, daemon=False)
    w.start()
    threads = [
        threading.Thread(target=collect_vehicles, args=(args.veh_period,), daemon=True),
        threading.Thread(target=collect_trips, args=(args.trip_period,), daemon=True),
    ]
    if args.lad_stops:
        threads.append(threading.Thread(
            target=collect_lad, args=(args.lad_period, args.lad_stops), daemon=True))
    for t in threads:
        t.start()
    log(f"collecting into {DB}")

    deadline = time.time() + args.hours * 3600 if args.hours else None
    try:
        while not stop_flag.is_set():
            if deadline and time.time() > deadline:
                break
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    stop_flag.set()
    time.sleep(1)
    writes.put(None)
    w.join()
    log("stopped")

