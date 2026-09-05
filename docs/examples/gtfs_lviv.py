"""Minimal shared helpers for the Lviv GTFS + GTFS-Realtime feeds.

pip install gtfs-realtime-bindings requests
"""
import csv, io, os, time, zipfile
import requests
from google.transit import gtfs_realtime_pb2

BASE = "https://track.ua-gis.com/gtfs/lviv"
CACHE = os.path.expanduser("~/.cache/lviv-gtfs")
STATIC_MAX_AGE = 24 * 3600


def static_zip():
    path = os.path.join(CACHE, "static.zip")
    if not os.path.exists(path) or time.time() - os.path.getmtime(path) > STATIC_MAX_AGE:
        os.makedirs(CACHE, exist_ok=True)
        data = requests.get(f"{BASE}/static.zip", timeout=120).content
        with open(path, "wb") as f:
            f.write(data)
    return zipfile.ZipFile(path)


def table(name):
    with static_zip().open(name) as f:
        return list(csv.DictReader(io.TextIOWrapper(f, "utf-8")))


def by_id(name, key):
    return {r[key]: r for r in table(name)}


def feed(endpoint):
    msg = gtfs_realtime_pb2.FeedMessage()
    msg.ParseFromString(requests.get(f"{BASE}/{endpoint}", timeout=30).content)
    return msg


def vehicle_type(short_name):
    if short_name.startswith("Тр"):
        return "trolleybus"
    if short_name.startswith("Т"):
        return "tram"
    return "bus"
