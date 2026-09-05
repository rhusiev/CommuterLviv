"""Does the official API model traffic downstream, or just propagate a delay?

The producer publishes no algorithm, so the only way to answer is to read the
predictions back. For one trip at one instant, take every stop it has yet to
reach and subtract that stop's scheduled time from its predicted time. That
difference is the delay the API thinks the trip is carrying.

If the API models the road ahead, the delay must drift from stop to stop: a
trip heading into a jam falls further behind with every stop. If instead the
delay is the same number at every downstream stop, the API measured one lateness
now and added it to a fixed timetable - no traffic in it at all.
"""
import datetime
import os
import sqlite3
import zoneinfo

import numpy as np

from . import gtfs, network

TZ = zoneinfo.ZoneInfo("Europe/Kyiv")
DB = os.path.join(gtfs.DATA, "feed.db")


def midnight(day):
    d = datetime.datetime.strptime(day, "%Y%m%d").replace(tzinfo=TZ)
    return d.timestamp()


def snapshots(net, db=DB, every=300.0, min_stops=4):
    """Rebuild the API's full prediction state at regular instants."""
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    rows = con.execute("SELECT poll_ts, trip_id, stop_id, t, start_date FROM pred "
                       "ORDER BY poll_ts").fetchall()
    con.close()
    if not rows:
        return []

    state = {}
    days = {}
    out = []
    t0 = rows[0][0]
    nxt = t0 + every
    idx = {}
    for poll_ts, trip, stop, t, day in rows:
        while poll_ts >= nxt:
            out.append((nxt, _read(net, state, days, idx, nxt, min_stops)))
            nxt += every
        state[(trip, stop)] = t
        if day:
            days[trip] = day
    return [(t, s) for t, s in out if s]


def _read(net, state, days, idx, now, min_stops):
    by_trip = {}
    for (trip, stop), t in state.items():
        if t < now:
            continue
        by_trip.setdefault(trip, []).append((stop, t))

    res = []
    for trip, items in by_trip.items():
        info = net.trip_stops.get(trip)
        day = days.get(trip)
        if info is None or day is None or len(items) < min_stops:
            continue
        ids, _, sched = info
        key = idx.get(trip)
        if key is None:
            key = idx[trip] = {}
            for i, s in enumerate(ids):
                key.setdefault(s, i)
        base = midnight(day)
        pos, delay = [], []
        for stop, t in items:
            i = key.get(stop)
            if i is None:
                continue
            pos.append(i)
            delay.append(t - (base + sched[i]))
        if len(pos) < min_stops:
            continue
        o = np.argsort(pos)
        res.append((trip, np.array(pos)[o], np.array(delay, dtype=float)[o]))
    return res


def report(net, **kw):
    snaps = snapshots(net, **kw)
    spreads, slopes, n = [], [], 0
    flat = 0
    for _, trips in snaps:
        for trip, pos, delay in trips:
            n += 1
            spread = delay.max() - delay.min()
            spreads.append(spread)
            if spread < 1.0:
                flat += 1
            if pos[-1] > pos[0]:
                slopes.append(np.polyfit(pos, delay, 1)[0])
    if not n:
        print("no snapshots yet")
        return
    spreads = np.sort(np.array(spreads))
    print(f"{len(snaps)} snapshots, {n} trip observations\n")
    print("Spread of predicted-minus-scheduled delay across a trip's downstream stops")
    for p in (10, 25, 50, 75, 90, 99):
        print(f"  p{p:<3d} {spreads[int(p / 100 * (len(spreads) - 1))]:8.1f} s")
    print(f"  exactly flat (<1 s across all stops): {flat}/{n} = {100 * flat / n:.1f}%")
    if slopes:
        sl = np.sort(np.array(slopes))
        print("\nDrift in delay per downstream stop (s/stop)")
        for p in (10, 50, 90):
            print(f"  p{p:<3d} {sl[int(p / 100 * (len(sl) - 1))]:+8.2f}")
    return snaps


def segments(net, **kw):
    """Compare the gap the API leaves between consecutive stops with the gap
    the timetable leaves. Equal gaps mean the timetable is being copied."""
    snaps = snapshots(net, **kw)
    same = 0
    tot = 0
    ratios = []
    for _, trips in snaps:
        for trip, pos, delay in trips:
            ids, _, sched = net.trip_stops[trip]
            d = np.diff(delay)
            s = np.diff(sched[pos])
            ok = s > 0
            tot += int(ok.sum())
            same += int((np.abs(d[ok]) < 1.0).sum())
            ratios.extend(((s[ok] + d[ok]) / s[ok]).tolist())
    if not tot:
        print("no segments")
        return
    r = np.sort(np.array(ratios))
    print(f"\n{tot} consecutive-stop segments across all trips and snapshots")
    print(f"  API segment time identical to timetable: {same}/{tot} = {100 * same / tot:.1f}%")
    print("  ratio API_segment / scheduled_segment")
    for p in (5, 25, 50, 75, 95):
        print(f"    p{p:<3d} {r[int(p / 100 * (len(r) - 1))]:.3f}")


def main():
    net = network.load()
    report(net)
    segments(net)

