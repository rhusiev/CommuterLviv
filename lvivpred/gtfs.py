"""Static GTFS access: cached download and table loading."""
import csv
import io
import os
import time
import zipfile

import requests

BASE = "https://track.ua-gis.com/gtfs/lviv"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
ZIP = os.path.join(DATA, "static.zip")
MAX_AGE = 24 * 3600

LAT_M = 111320.0


def static_zip():
    """The cached static feed, re-fetched once a day.

    An unchanged feed keeps its file untouched and only has its timestamp
    bumped, so anything caching work derived from it - the network geometry
    above all - can tell a genuinely new feed from a daily re-download by
    modification time alone.
    """
    if not os.path.exists(ZIP) or time.time() - os.path.getmtime(ZIP) > MAX_AGE:
        os.makedirs(DATA, exist_ok=True)
        body = requests.get(f"{BASE}/static.zip", timeout=180).content
        if os.path.exists(ZIP) and open(ZIP, "rb").read() == body:
            os.utime(ZIP)
        else:
            tmp = ZIP + ".tmp"
            with open(tmp, "wb") as f:
                f.write(body)
            os.replace(tmp, ZIP)
    return zipfile.ZipFile(ZIP)


def table(name):
    with static_zip().open(name) as f:
        return list(csv.DictReader(io.TextIOWrapper(f, "utf-8")))


def vehicle_type(short_name):
    if short_name.startswith("Тр"):
        return "trolleybus"
    if short_name.startswith("Т"):
        return "tram"
    return "bus"

