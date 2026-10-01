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
    """The cached static feed, re-fetched once a day."""
    if not ZIP.exists() or time.time() - ZIP.stat().st_mtime > MAX_AGE:
        refetch()
    return zipfile.ZipFile(ZIP)


def refetch():
    """Downloads the feed now; whether it differs from the one held.

    An unchanged feed keeps its bytes and only gets its mtime bumped, so callers
    caching derived work can tell a new feed from a re-download by mtime alone.
    """
    DATA.mkdir(parents=True, exist_ok=True)
    res = requests.get(f"{BASE}/static.zip", timeout=180)
    # the server serves error pages as 200, so a bad body must not be cached
    res.raise_for_status()
    body = res.content
    if ZIP.exists() and ZIP.read_bytes() == body:
        os.utime(ZIP)
        return False
    try:
        with zipfile.ZipFile(io.BytesIO(body)) as z:
            missing = {"routes.txt", "trips.txt", "stop_times.txt"}
            missing -= set(z.namelist())
    except zipfile.BadZipFile:
        missing = {"a zip"}
    if missing:
        raise ValueError(f"the feed came without {', '.join(sorted(missing))}")
    tmp = DATA / "static.zip.tmp"
    tmp.write_bytes(body)
    tmp.replace(ZIP)
    return True


def table(name, optional=False):
    with static_zip() as z:
        if optional and name not in z.namelist():
            return []
        with z.open(name) as f:
            return list(csv.DictReader(io.TextIOWrapper(f, "utf-8")))


class Calendar:
    """Which services run on a date: calendar.txt's weekdays within its date
    range, overridden by calendar_dates.txt. GTFS makes both optional, and a
    feed with neither is taken to run every service every day."""

    DAYS = ("monday", "tuesday", "wednesday", "thursday", "friday",
            "saturday", "sunday")

    def __init__(self):
        self.weekly = {
            r["service_id"]: ({i for i, d in enumerate(self.DAYS) if r[d] == "1"},
                              r["start_date"], r["end_date"])
            for r in table("calendar.txt", optional=True)}
        self.changed = {}  # "YYYYMMDD" -> {service_id: added, not removed}
        for r in table("calendar_dates.txt", optional=True):
            self.changed.setdefault(r["date"], {})[r["service_id"]] = \
                r["exception_type"] == "1"

    def runs(self, service, day):
        key = day.strftime("%Y%m%d")
        added = self.changed.get(key, {}).get(service)
        if added is not None:
            return added
        if not self.weekly and not self.changed:
            return True
        days, first, last = self.weekly.get(service, ((), "", ""))
        return day.weekday() in days and first <= key <= last


def vehicle_type(short_name):
    if short_name.startswith("Тр"):
        return "trolleybus"
    if short_name.startswith("Т"):
        return "tram"
    return "bus"

