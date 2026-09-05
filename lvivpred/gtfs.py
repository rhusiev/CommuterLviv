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
    if not os.path.exists(ZIP) or time.time() - os.path.getmtime(ZIP) > MAX_AGE:
        os.makedirs(DATA, exist_ok=True)
        body = requests.get(f"{BASE}/static.zip", timeout=180).content
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

