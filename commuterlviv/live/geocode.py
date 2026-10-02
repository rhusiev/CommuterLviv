"""Names of places, from OpenStreetMap: a local index first, then Photon.

The local index is osm-mapidx's (`data/lviv-search.sqlite`).
`.github/workflows/places.yml` rebuilds it from OpenStreetMap monthly and
publishes it, and `renew_index` downloads it at that pace. It survives typos
and knows each place's surroundings, so "аптека сихів" and "форум львв" both find what was meant, and
it answers without leaving the machine. It has no house numbers.

Photon (https://photon.komoot.io) fills that in. It is used rather than
Nominatim because it indexes every named object in OSM and answers a prefix,
which is what a search box needs: "vul. Ho" finds the street. The public
instance asks that anyone leaning on it run their own, which is one setting
away: point COMMUTERLVIV_PHOTON_URL at it.

Either source alone is enough to search; with neither the endpoint answers 503.
"""
import os
import threading
import time
import urllib.parse

import requests

from .. import __version__, gtfs, walk
from ..mapidx import search as mapidx

INDEX = gtfs.DATA / "lviv-search.sqlite"
INDEX_EVERY = 30 * 86400.0      # s between index refetches

# the city's box, also what the footpath graph covers
SOUTH, NORTH, WEST, EAST = 49.7, 50.05, 23.8, 24.25
CENTRE = (49.8419, 24.0315)

TTL = 86400.0
ENTRIES = 2000          # a day of queries from a city-sized audience
LIMIT = 8
TIMEOUT = 4.0

# m apart two hits of the same name are one place said twice
SAME_PLACE = 100.0
# the index covers the whole oblast and ranks by name before distance, so
# enough hits are asked for that the city's survive the clamp
WIDE = 300
# mapidx addresses open with the nearest settlements; the street and district follow
NEAR = 3

# Photon indexes names in the local language under "default"; it translates
# only into the handful it was built with, and Ukrainian is not one of them
LANG = "default"

AGENT = f"CommuterLviv/{__version__} (+https://github.com/rhusiev/CommuterLviv)"


def inside(lat, lon):
    return SOUTH <= lat <= NORTH and WEST <= lon <= EAST


class Geocoder:
    """The local index and a Photon instance, with an answer cache in front.

    The cache is what keeps typing cheap: a search box asks once per keystroke,
    and every prefix of a word anyone has typed today is already an answer.
    """

    def __init__(self, url, lang=LANG, index=INDEX):
        self.url = url.rstrip("/")
        self.lang = lang
        self.index = index
        self.session = requests.Session()
        self.session.headers["user-agent"] = AGENT
        self.lock = threading.Lock()
        self.cache = {}

    def find(self, q):
        key = " ".join(q.lower().split())
        if not key:
            return []
        now = time.time()
        with self.lock:
            hit = self.cache.get(key)
            if hit and now - hit[0] < TTL:
                return hit[1]
        found = self._merge(key)
        with self.lock:
            if len(self.cache) >= ENTRIES:
                self.cache.clear()
            self.cache[key] = (now, found)
        return found

    def ready(self):
        """Whether there is anything to search with; the index may still be
        on its way."""
        return bool(self.url) or self.index.exists()

    def _merge(self, q):
        """Both sources, one list. A digit means a house address, which only
        Photon knows, so it leads; otherwise the local index does. Photon
        failing is fatal only when it was the one source."""
        local = self._local(q)
        try:
            remote = self._ask(q) if self.url else []
        except requests.RequestException:
            if not self.index.exists():
                raise
            remote = []
        first, then = (remote, local) if any(c.isdigit() for c in q) \
            else (local, remote)
        out = []
        for p in first + then:
            if not any(_same(p, o) for o in out):
                out.append(p)
        return out[:LIMIT]

    def _local(self, q):
        if not self.index.exists():
            return []
        hits = mapidx.search(str(self.index), q, limit=WIDE, origin=CENTRE)
        return [{"name": h["name"], "where": ", ".join(h["address"][NEAR:NEAR + 2]),
                 "lat": h["lat"], "lon": h["lon"], "kind": None}
                for h in hits if inside(h["lat"], h["lon"])][:LIMIT]

    def _ask(self, q):
        query = urllib.parse.urlencode({
            "q": q, "limit": LIMIT, "lang": self.lang,
            "lat": CENTRE[0], "lon": CENTRE[1],
            "bbox": f"{WEST},{SOUTH},{EAST},{NORTH}",
        })
        r = self.session.get(f"{self.url}/api?{query}", timeout=TIMEOUT)
        r.raise_for_status()
        out = []
        for f in r.json().get("features", []):
            place = _place(f)
            if place is not None:
                out.append(place)
        return out


def index_age(path=INDEX):
    return time.time() - path.stat().st_mtime if path.exists() else float("inf")


def renew_index(url, path=INDEX):
    """Downloads the index beside the one held and swaps it in once it answers.
    Searches open the file per query, so one in flight keeps reading the old."""
    fresh = path.with_name("lviv-search.next.sqlite")
    try:
        with requests.get(url, stream=True, timeout=60,
                          headers={"user-agent": AGENT}) as r:
            r.raise_for_status()
            with open(fresh, "wb") as f:
                for chunk in r.iter_content(1 << 20):
                    f.write(chunk)
        if not mapidx.search(str(fresh), "львів", limit=1):
            raise ValueError("the downloaded index does not find Lviv")
        os.replace(fresh, path)
    finally:
        fresh.unlink(missing_ok=True)


def _same(a, b):
    return a["name"] == b["name"] and \
        walk.metres(a["lat"], a["lon"], b["lat"], b["lon"]) < SAME_PLACE


def _place(f):
    """One Photon feature as a row of the search list, or None when it is
    outside the city - the bbox biases the ranking, it does not bound it."""
    try:
        lon, lat = f["geometry"]["coordinates"][:2]
    except (KeyError, IndexError, TypeError):
        return None
    if not inside(lat, lon):
        return None
    p = f.get("properties", {})
    name = p.get("name") or _street(p)
    if not name:
        return None
    return {"name": name, "where": _where(p, name),
            "lat": float(lat), "lon": float(lon), "kind": p.get("osm_value")}


def _street(p):
    house = p.get("housenumber")
    street = p.get("street")
    if not street:
        return None
    return f"{street} {house}" if house else street


def _where(p, name):
    """The line under the name: enough to tell two identical names apart."""
    parts = [_street(p), p.get("district"), p.get("city")]
    return ", ".join(dict.fromkeys(x for x in parts if x and x != name))
