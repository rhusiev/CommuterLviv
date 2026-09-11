"""Names of places, from OpenStreetMap, through Photon.

Photon (https://photon.komoot.io) is used rather than Nominatim because it
indexes every named object in OSM and answers a prefix, which is what a search
box needs: "vul. Ho" finds the street, and "Forum" finds the shopping centre.
Nominatim answers whole addresses well and little else.

The public instance asks that anyone leaning on it run their own, which is one
setting away: point COMMUTERLVIV_PHOTON_URL at it.
"""
import threading
import time
import urllib.parse

import requests

from .. import __version__

# the city's box, also what the footpath graph covers
SOUTH, NORTH, WEST, EAST = 49.7, 50.05, 23.8, 24.25
CENTRE = (49.8419, 24.0315)

TTL = 86400.0
ENTRIES = 2000          # a day of queries from a city-sized audience
LIMIT = 8
TIMEOUT = 4.0

# Photon indexes names in the local language under "default"; it translates
# only into the handful it was built with, and Ukrainian is not one of them
LANG = "default"

AGENT = f"CommuterLviv/{__version__} (+https://github.com/rhusiev/CommuterLviv)"


def inside(lat, lon):
    return SOUTH <= lat <= NORTH and WEST <= lon <= EAST


class Geocoder:
    """A Photon instance, with an answer cache in front of it.

    The cache is what keeps typing cheap: a search box asks once per keystroke,
    and every prefix of a word anyone has typed today is already an answer.
    """

    def __init__(self, url, lang=LANG):
        self.url = url.rstrip("/")
        self.lang = lang
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
        found = self._ask(key)
        with self.lock:
            if len(self.cache) >= ENTRIES:
                self.cache.clear()
            self.cache[key] = (now, found)
        return found

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
