#!/usr/bin/env python3
"""Arrivals at one stop via api.lad.lviv.ua - one call, no protobuf.

    python3 stop_arrivals.py 61          # by stop_code
    python3 stop_arrivals.py Ринок       # by name, resolved through static GTFS
"""
import datetime, re, sys, requests
from gtfs_lviv import table

BASE = "https://api.lad.lviv.ua"


def codes_for(query):
    if query.isdigit():
        return [query]
    hits = [s for s in table("stops.txt")
            if query.casefold() in s["stop_name"].casefold() and s["stop_code"].isdigit()]
    return [s["stop_code"].lstrip("0") for s in hits]


def show(code):
    r = requests.get(f"{BASE}/stops/{code}", timeout=15)
    if r.status_code != 200:
        print(f"stop {code}: {r.status_code} {r.text.strip()[:60]}")
        return
    d = r.json()
    print(f"\n{d['name']} ({d['eng_name']}) - code {d['code']}")

    now = datetime.datetime.now(datetime.timezone.utc)
    for t in d["timetable"]:
        when = datetime.datetime.strptime(
            t["arrival_time"], "%a, %d %b %Y %H:%M:%S %Z"
        ).replace(tzinfo=datetime.timezone.utc)
        live = "sched" if t.get("scheduled") else f"veh {t['vehicle_id']}"
        print(f"  {t['route']:>5} {t['vehicle_type']:<10} "
              f"{(when - now).total_seconds() / 60:5.1f} min  "
              f"{'LF' if t['lowfloor'] else '  '} {live:<10} -> {t['end_stop_name']}")
    if not d["timetable"]:
        print("  nothing due")


def main(query):
    found = codes_for(query)
    if not found:
        print(f"no stop matching {query!r}")
        return 1
    for code in found[:5]:
        show(code)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
