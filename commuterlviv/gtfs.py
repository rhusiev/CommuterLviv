"""Static GTFS access: cached download and table loading."""
import csv
import io
import os
import time
import zipfile
from pathlib import Path

import requests

BASE = "https://track.ua-gis.com/gtfs/lviv"
ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
ZIP = DATA / "static.zip"
MAX_AGE = 24 * 3600

LAT_M = 111320.0


def static_zip():
    """The cached static feed, re-fetched once a day.

    An unchanged feed keeps its bytes and only gets its mtime bumped, so callers
    caching derived work can tell a new feed from a re-download by mtime alone.
    """
    if not ZIP.exists() or time.time() - ZIP.stat().st_mtime > MAX_AGE:
        DATA.mkdir(parents=True, exist_ok=True)
        res = requests.get(f"{BASE}/static.zip", timeout=180)
        # the server serves error pages as 200, so a bad body must not be cached
        res.raise_for_status()
        body = res.content
        if ZIP.exists() and ZIP.read_bytes() == body:
            os.utime(ZIP)
        else:
            tmp = DATA / "static.zip.tmp"
            tmp.write_bytes(body)
            tmp.replace(ZIP)
    return zipfile.ZipFile(ZIP)


def table(name):
    with static_zip() as z, z.open(name) as f:
        return list(csv.DictReader(io.TextIOWrapper(f, "utf-8")))


def vehicle_type(short_name):
    if short_name.startswith("Тр"):
        return "trolleybus"
    if short_name.startswith("Т"):
        return "tram"
    return "bus"

