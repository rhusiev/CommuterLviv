"""Continuously record the three Lviv feeds into SQLite.

  vehicle_position -> veh    (deduped on the GPS fix timestamp)
  trip_updates     -> pred   (stored only when a prediction moves materially)
  api.lad.lviv.ua  -> lad    (a rotating sample of stops)

Rows are only ever appended, so the evaluator can replay any past moment.

This is meant to be left running for days, so every part of it is written to
survive rather than to be correct once. A feed that starts failing backs off
instead of hammering; a write that fails is retried and then dropped rather than
killing the thread that would have written everything after it; the queue is
bounded so a stalled disk cannot turn into an out-of-memory kill; and the run
stops itself cleanly while there is still disk left rather than dying when
there is none. A heartbeat line every few minutes says which of those is
happening.
"""
import argparse
import collections
import datetime
import os
import queue
import shutil
import signal
import sqlite3
import threading
import time

import requests
from google.transit import gtfs_realtime_pb2

from .gtfs import BASE, DATA, table

DB = os.path.join(DATA, "feed.db")

QUEUE_MAX = 500_000      # rows buffered before new ones are dropped
BATCH_S = 2.0            # how often the writer commits
CHECKPOINT_S = 300.0     # how often the write-ahead log is folded back in
HEARTBEAT_S = 300.0
BACKOFF_MAX = 120.0      # s between attempts at a feed that keeps failing

SCHEMA = """
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA auto_vacuum=INCREMENTAL;

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
writes = queue.Queue(maxsize=QUEUE_MAX)
stats = collections.Counter()
stats_lock = threading.Lock()


def log(*a):
    print(datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"), *a, flush=True)


def count(**kw):
    with stats_lock:
        stats.update(kw)


def emit(kind, row):
    """Queue a row. Drops rather than blocks: a stalled writer must not stall
    collection, and an unbounded backlog is how a long run runs out of memory."""
    try:
        writes.put_nowait((kind, row))
    except queue.Full:
        count(dropped=1)


def writer():
    db = None
    pending = collections.defaultdict(list)
    last_write = last_ckpt = time.time()
    sql = {
        "poll": "INSERT INTO poll VALUES(?,?,?,?,?,?)",
        "veh": "INSERT OR IGNORE INTO veh VALUES(?,?,?,?,?,?,?,?,?,?,?)",
        "pred": "INSERT INTO pred VALUES(?,?,?,?,?,?,?,?,?)",
        "lad": "INSERT INTO lad VALUES(?,?,?,?,?,?,?,?,?)",
    }

    def flush():
        """Commit what is pending. A batch that will not go in twice is dropped:
        losing a few seconds of one feed beats losing every later second of all
        of them."""
        nonlocal db
        for attempt in (0, 1):
            try:
                if db is None:
                    db = sqlite3.connect(DB, timeout=60)
                    db.executescript(SCHEMA)
                for kind, rows in pending.items():
                    db.executemany(sql[kind], rows)
                db.commit()
                count(written=sum(len(r) for r in pending.values()))
                pending.clear()
                return
            except sqlite3.Error as exc:
                log("write failed", repr(exc)[:200])
                count(write_errors=1)
                try:
                    if db is not None:
                        db.close()
                except sqlite3.Error:
                    pass
                db = None
                if attempt:
                    count(dropped=sum(len(r) for r in pending.values()))
                    pending.clear()
                else:
                    time.sleep(2.0)

    done = False
    while not done:
        try:
            item = writes.get(timeout=1.0)
            if item is None:
                done = True
            else:
                pending[item[0]].append(item[1])
        except queue.Empty:
            pass
        now = time.time()
        if pending and (done or now - last_write > BATCH_S):
            flush()
            last_write = now
        if db is not None and now - last_ckpt > CHECKPOINT_S:
            try:
                db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
                db.execute("PRAGMA incremental_vacuum")
            except sqlite3.Error as exc:
                log("checkpoint failed", repr(exc)[:200])
            last_ckpt = now
    if db is not None:
        db.close()


def poll_loop(feed, period, once):
    """Run `once` forever, backing off while it keeps failing.

    A feed that is down stays down for minutes at a time. Retrying it every
    5 s achieves nothing, fills the poll table with identical errors and looks
    like abuse from the far end, so each consecutive failure doubles the wait
    up to two minutes. One success clears it.
    """
    fails = 0
    while not stop_flag.is_set():
        t0 = time.time()
        try:
            n, header = once()
            emit("poll", (t0, feed, header, n, int((time.time() - t0) * 1000), None))
            count(**{f"{feed}_rows": n, f"{feed}_polls": 1})
            fails = 0
        except Exception as exc:
            emit("poll", (t0, feed, 0, 0, int((time.time() - t0) * 1000),
                          repr(exc)[:200]))
            count(**{f"{feed}_errors": 1})
            fails += 1
            if fails in (1, 5) or fails % 50 == 0:
                log(f"{feed} error x{fails}", repr(exc)[:150])
        wait = min(period * 2 ** min(fails, 16), BACKOFF_MAX) if fails else period
        stop_flag.wait(max(0.5, wait - (time.time() - t0)))


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
            time.sleep(0.5 * 2 ** attempt)


def vehicles():
    seen = {}

    def once():
        t0 = time.time()
        msg = rt("vehicle_position")
        n = 0
        for e in msg.entity:
            v = e.vehicle
            key = v.vehicle.id
            if seen.get(key) == v.timestamp:
                continue
            seen[key] = v.timestamp
            p = v.position
            emit("veh", (key, v.timestamp, v.trip.route_id or None,
                         v.trip.trip_id or None, p.latitude, p.longitude,
                         p.bearing, p.speed, p.odometer, t0,
                         v.vehicle.label or None))
            n += 1
        return n, msg.header.timestamp
    return once


def trips(deadband):
    """One row per prediction that actually moved.

    The feed republishes every stop of every trip on every poll, and most of
    what changes between two polls is a second or two of jitter on a number
    that is scored against a 60 s grid. Storing those costs 85% of the database
    and buys nothing, so a prediction is recorded only once it has moved
    further than the deadband from the last value stored for that stop.
    """
    last = {}

    def once():
        t0 = time.time()
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
                prev = last.get(key)
                if prev is not None and prev[0] == kind and abs(prev[1] - t) <= deadband:
                    continue
                last[key] = (kind, t)
                emit("pred", (t0, tu.trip.trip_id, tu.vehicle.id or None,
                              tu.trip.route_id, stu.stop_id, stu.stop_sequence,
                              kind, t, tu.trip.start_date or None))
                n += 1
        if len(last) > 2_000_000:
            last.clear()
        return n, msg.header.timestamp
    return once


def lad_stop_codes(limit):
    counts = collections.Counter(r["stop_id"] for r in table("stop_times.txt"))
    stops = table("stops.txt")
    by_code = collections.Counter(s["stop_code"] for s in stops if s["stop_code"])
    ok = [s for s in stops
          if s["stop_code"].isdigit() and by_code[s["stop_code"]] == 1]
    ok.sort(key=lambda s: -counts.get(s["stop_id"], 0))
    return [s["stop_code"].lstrip("0") or "0" for s in ok[:limit]]


def collect_lad(period, limit):
    """One stop at a time, spread evenly over the period.

    The board is per-stop, so covering 40 stops means 40 requests. They are
    spaced rather than burst so the far end sees a steady trickle.
    """
    codes = lad_stop_codes(limit)
    log(f"lad sampling {len(codes)} stops")
    gap = period / max(1, len(codes))
    session = requests.Session()
    while not stop_flag.is_set():
        cycle = time.time()
        for code in codes:
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
                    emit("lad", (t0, code, e.get("route"), e.get("route_id"),
                                 e.get("vehicle_id"), 1 if e.get("scheduled") else 0,
                                 int(when.timestamp()), e.get("end_stop_name"),
                                 e.get("direction_id")))
                emit("poll", (t0, "lad", 0, len(rows), int((time.time() - t0) * 1000),
                              None if r.status_code == 200 else str(r.status_code)))
                count(lad_rows=len(rows), lad_polls=1)
            except Exception as exc:
                emit("poll", (t0, "lad", 0, 0, int((time.time() - t0) * 1000),
                              repr(exc)[:200]))
                count(lad_errors=1)
            stop_flag.wait(max(0.05, gap - (time.time() - t0)))
        stop_flag.wait(max(0.5, period - (time.time() - cycle)))


def db_bytes():
    return sum(os.path.getsize(DB + s) for s in ("", "-wal", "-shm")
               if os.path.exists(DB + s))


def prune(keep_days):
    """Drop rows older than the retention window and give the space back.

    Only useful on a database created by this version, which asks SQLite for
    incremental auto-vacuum up front; without that a delete frees pages inside
    the file but never shrinks it.
    """
    cutoff = time.time() - keep_days * 86400
    db = sqlite3.connect(DB, timeout=60)
    try:
        for t, col in (("veh", "poll_ts"), ("pred", "poll_ts"),
                       ("lad", "poll_ts"), ("poll", "ts")):
            db.execute(f"DELETE FROM {t} WHERE {col} < ?", (cutoff,))
        db.commit()
        db.execute("PRAGMA incremental_vacuum")
        db.commit()
    finally:
        db.close()


def heartbeat(min_free_gb, keep_days):
    """The one line that says whether a multi-day run is still healthy.

    It is also the only thing that stops the run before the disk does. Filling
    a disk takes the database down with it - and often the rest of the machine
    - so collection ends while there is still room to close the file cleanly.
    """
    last_prune = time.time()
    while not stop_flag.wait(HEARTBEAT_S):
        with stats_lock:
            s = dict(stats)
        free = shutil.disk_usage(DATA).free
        log(f"veh {s.get('veh_rows', 0)}/{s.get('veh_polls', 0)}p  "
            f"pred {s.get('pred_rows', 0)}/{s.get('pred_polls', 0)}p  "
            f"lad {s.get('lad_rows', 0)}/{s.get('lad_polls', 0)}p  "
            f"errors {s.get('veh_errors', 0)}/{s.get('pred_errors', 0)}/"
            f"{s.get('lad_errors', 0)}  "
            f"queue {writes.qsize()}  dropped {s.get('dropped', 0)}  "
            f"db {db_bytes() / 2**30:.2f}G  free {free / 2**30:.1f}G")
        if free < min_free_gb * 2**30:
            log(f"only {free / 2**30:.1f}G free, stopping while the database "
                f"can still be closed cleanly")
            stop_flag.set()
            return
        if keep_days and time.time() - last_prune > 3600:
            try:
                prune(keep_days)
            except sqlite3.Error as exc:
                log("prune failed", repr(exc)[:200])
            last_prune = time.time()


def main(argv=None):
    ap = argparse.ArgumentParser(prog="lvivpred collect")
    ap.add_argument("--veh-period", type=float, default=5.0)
    ap.add_argument("--trip-period", type=float, default=15.0)
    ap.add_argument("--lad-period", type=float, default=60.0)
    ap.add_argument("--lad-stops", type=int, default=40,
                    help="0 disables the api.lad.lviv.ua board entirely")
    ap.add_argument("--pred-deadband", type=float, default=5.0,
                    help="seconds a trip_updates prediction must move to be stored")
    ap.add_argument("--keep-days", type=float, default=0,
                    help="drop rows older than this; 0 keeps everything")
    ap.add_argument("--min-free-gb", type=float, default=2.0,
                    help="stop cleanly when the disk falls below this")
    ap.add_argument("--hours", type=float, default=0,
                    help="stop after this long; 0 runs until told to stop")
    args = ap.parse_args(argv)

    os.makedirs(DATA, exist_ok=True)
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: stop_flag.set())

    w = threading.Thread(target=writer, daemon=False)
    w.start()
    threads = [
        threading.Thread(target=poll_loop,
                         args=("veh", args.veh_period, vehicles()), daemon=True),
        threading.Thread(target=poll_loop,
                         args=("pred", args.trip_period,
                               trips(args.pred_deadband)), daemon=True),
        threading.Thread(target=heartbeat,
                         args=(args.min_free_gb, args.keep_days), daemon=True),
    ]
    if args.lad_stops:
        threads.append(threading.Thread(
            target=collect_lad, args=(args.lad_period, args.lad_stops), daemon=True))
    for t in threads:
        t.start()
    log(f"collecting into {DB}, {shutil.disk_usage(DATA).free / 2**30:.1f}G free")

    deadline = time.time() + args.hours * 3600 if args.hours else None
    while not stop_flag.wait(1.0):
        if deadline and time.time() > deadline:
            break
    stop_flag.set()
    time.sleep(1.5)
    writes.put(None)
    w.join()
    with stats_lock:
        log("stopped;", dict(stats))
