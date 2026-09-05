#!/usr/bin/env python3
"""Live arrivals for the stops nearest a coordinate.

    python3 arrivals.py 49.8419 24.0315
"""
import math, re, sys, time
from gtfs_lviv import by_id, table, feed, vehicle_type

RADIUS_M = 150  # groups both directions of one street corner


def metres(a, b):
    dy = (a[0] - b[0]) * 111320
    dx = (a[1] - b[1]) * 111320 * math.cos(math.radians(a[0]))
    return math.hypot(dx, dy)


def main(lat, lon):
    stops = table("stops.txt")
    routes = by_id("routes.txt", "route_id")

    near = [s for s in stops
            if metres((lat, lon), (float(s["stop_lat"]), float(s["stop_lon"]))) <= RADIUS_M]
    if not near:
        print("no stops within %d m" % RADIUS_M)
        return 1
    wanted = {s["stop_id"]: s for s in near}
    label = re.sub(r"\s*\(\d+\)\s*$", "", near[0]["stop_name"])

    rows = []
    for e in feed("trip_updates").entity:
        tu = e.trip_update
        for stu in tu.stop_time_update:
            if stu.stop_id not in wanted:
                continue
            when = (stu.arrival.time or stu.departure.time)
            if not when:
                continue
            rows.append((when, tu.trip.route_id, tu.vehicle.id, wanted[stu.stop_id]))

    print(f"{label} - {len(near)} stop(s), {len(rows)} arrivals\n")
    now = time.time()
    for when, route_id, veh, stop in sorted(rows)[:15]:
        r = routes.get(route_id, {})
        name = r.get("route_short_name", "?")
        print(f"{name:>5} {vehicle_type(name):<10} {(when - now) / 60:5.1f} min  "
              f"{time.strftime('%H:%M', time.localtime(when))}  "
              f"veh {veh:<5} {stop['stop_name']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(float(sys.argv[1]), float(sys.argv[2])))
