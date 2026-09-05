#!/usr/bin/env python3
"""Every vehicle currently moving in Lviv, with route names joined in."""
import sys, time
from gtfs_lviv import by_id, feed, vehicle_type


def main():
    routes = by_id("routes.txt", "route_id")
    msg = feed("vehicle_position")
    print(f"{len(msg.entity)} vehicles @ {time.ctime(msg.header.timestamp)}\n")

    for e in sorted(msg.entity, key=lambda e: e.vehicle.trip.route_id):
        v, p = e.vehicle, e.vehicle.position
        r = routes.get(v.trip.route_id, {})
        name = r.get("route_short_name", "?")
        print(f"{name:>5} {vehicle_type(name):<10} {p.latitude:.5f},{p.longitude:.5f} "
              f"{p.speed * 3.6:5.1f} km/h brg {p.bearing:3.0f}  "
              f"veh {v.vehicle.id:<5} {v.vehicle.license_plate:<10} "
              f"{'LF' if v.vehicle.label == 'low_floor' else '  '} "
              f"{r.get('route_long_name', '')}")


if __name__ == "__main__":
    sys.exit(main())
