"""The city on foot: an OpenStreetMap footpath graph, and shortest walks on it.

A journey is walk, ride, walk, and the two walks decide most of it - which
stops are worth boarding at, and how long the door-to-door total really is.
Straight-line distance will not do that: the river of a railway line, a fenced
yard or a four-lane road with one crossing all make a stop 200 m away a
six-minute walk, and a planner that believes the crow suggests boarding at
stops nobody can reach.

The graph comes from Overpass rather than a Geofabrik extract because the
whole of Ukraine is a gigabyte to answer a question about one city, and it is
fetched once and cached: `data/walk.npz`. Refetching is a deliberate act
(`python -m commuterlviv walk --refresh`), so no request this service serves
ever waits on an external API.

Nothing here knows about time tables. It answers one question - how many
seconds of walking from these points to everywhere nearby - and `plan.py`
decides what to do with the answer.
"""
import heapq
import math
import time
from pathlib import Path

import numpy as np
import requests

from . import network

DATA = Path(__file__).resolve().parent.parent / "data"
CACHE = DATA / "walk.npz"

OVERPASS = "https://overpass-api.de/api/interpreter"

# Not politeness: the Apache in front of Overpass answers 406 Not Acceptable to
# a POST with no User-Agent, with an HTML error page that mentions nothing
# about the header
AGENT = "commuterlviv/1.0 (+https://github.com/rad1an/commuterlviv)"

# m/s. An unhurried adult on flat pavement, and slow enough to be honest about
# crossings and kerbs, which the graph does not model
SPEED = 1.3

# Ways somebody on foot may use. `highway=service` is in because yards and
# petrol-station aprons are how a great many stops are actually reached;
# motorways and their links are out because they are not walkable at all
WALKABLE = {
    "footway", "path", "pedestrian", "steps", "living_street", "residential",
    "service", "unclassified", "tertiary", "secondary", "primary",
    "tertiary_link", "secondary_link", "primary_link", "track", "road",
    "crossing", "corridor",
}

# Margin in degrees around the stops' bounding box: about 2 km, so that a walk
# that leaves the box and comes back still has ground under it
MARGIN = 0.02


def query(bbox):
    """The Overpass query for one bounding box. Ways only: the nodes come back
    with them through `>`, and every other tag is weight nobody reads."""
    south, west, north, east = bbox
    kinds = "|".join(sorted(WALKABLE))
    return f"""[out:json][timeout:180];
way["highway"~"^({kinds})$"]["foot"!="no"]["access"!="private"]
   ({south},{west},{north},{east});
(._;>;);
out skel qt;"""


def bbox(net):
    lat = [s["lat"] for s in net.stops.values()]
    lon = [s["lon"] for s in net.stops.values()]
    return (min(lat) - MARGIN, min(lon) - MARGIN,
            max(lat) + MARGIN, max(lon) + MARGIN)


def fetch(net=None, session=None):
    """The raw Overpass answer. Minutes, and rate limited at the far end, so
    this is called by hand and not by the service."""
    net = net or network.load()
    get = session or requests
    res = get.post(OVERPASS, data={"data": query(bbox(net))}, timeout=600,
                   headers={"User-Agent": AGENT})
    res.raise_for_status()
    return res.json()


def metres(lat1, lon1, lat2, lon2):
    """Equirectangular, which over a city block is exact to a centimetre and
    costs no trigonometry per edge beyond one cosine per pair."""
    k = math.cos(math.radians((lat1 + lat2) / 2))
    return math.hypot((lat2 - lat1) * 111320.0, (lon2 - lon1) * 111320.0 * k)


def compile_graph(raw):
    """Overpass JSON into the arrays `Walk` runs on.

    Only nodes a way actually uses are kept, and the ways become undirected
    edges: one-way streets are one-way for traffic, not for pedestrians.
    """
    where = {}
    ways = []
    for el in raw["elements"]:
        if el["type"] == "node":
            where[el["id"]] = (el["lat"], el["lon"])
        elif el["type"] == "way":
            ways.append(el["nodes"])

    used = {}
    lat, lon = [], []
    for nodes in ways:
        for n in nodes:
            if n in used or n not in where:
                continue
            used[n] = len(lat)
            lat.append(where[n][0])
            lon.append(where[n][1])

    heads, tails, costs = [], [], []
    for nodes in ways:
        prev = None
        for n in nodes:
            i = used.get(n)
            if i is None:
                continue
            if prev is not None:
                d = metres(lat[prev], lon[prev], lat[i], lon[i])
                heads.append(prev)
                tails.append(i)
                costs.append(d)
            prev = i

    lat = np.array(lat)
    lon = np.array(lon)
    # Both directions, then sorted by tail so the neighbours of a node are one
    # contiguous slice - the shape a Dijkstra wants to read
    a = np.array(heads + tails, dtype=np.int32)
    b = np.array(tails + heads, dtype=np.int32)
    w = np.array(costs + costs, dtype=np.float32)
    order = np.argsort(a, kind="stable")
    a, b, w = a[order], b[order], w[order]
    start = np.searchsorted(a, np.arange(len(lat) + 1)).astype(np.int64)
    return lat, lon, b, w, start


def save(path=CACHE, raw=None):
    raw = raw or fetch()
    lat, lon, to, w, start = compile_graph(raw)
    path.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(path, lat=lat, lon=lon, to=to, cost=w, start=start,
                        built=np.array([time.time()]))
    return path


class Walk:
    """A footpath graph, and the walks that start anywhere on it.

    The graph is nodes with a neighbour list each; `near` finds the ones close
    to a point through a coarse grid, and `reach` is a Dijkstra that stops at a
    time limit rather than at a distance, because seconds are what a journey is
    compared in.
    """

    def __init__(self, lat, lon, to, cost, start):
        self.lat, self.lon = lat, lon
        self.to, self.cost, self.start = to, cost, start
        # A grid of about 200 m, which holds a handful of nodes per cell
        self.cell = 0.002
        self.grid = {}
        for i, (a, o) in enumerate(zip(lat, lon)):
            self.grid.setdefault((int(a / self.cell), int(o / self.cell)),
                                 []).append(i)

    @classmethod
    def load(cls, path=CACHE):
        with np.load(path) as z:
            return cls(z["lat"], z["lon"], z["to"], z["cost"], z["start"])

    def near(self, lat, lon, within=150.0):
        """Every node within `within` metres, nearest first. Empty means the
        point is off the graph - in a field, or outside the fetched box - and
        the caller has to say so rather than guess a route from nowhere."""
        r = int(within / (self.cell * 111320.0)) + 1
        cy, cx = int(lat / self.cell), int(lon / self.cell)
        found = []
        for y in range(cy - r, cy + r + 1):
            for x in range(cx - r, cx + r + 1):
                for i in self.grid.get((y, x), ()):
                    d = metres(lat, lon, self.lat[i], self.lon[i])
                    if d <= within:
                        found.append((d, i))
        found.sort()
        return found

    def reach(self, sources, limit_s):
        """Seconds of walking from the nearest source to every node within
        `limit_s`, as a dict. `sources` are `(node, seconds already spent)`,
        which is how the walk from a doorway onto the graph is paid for."""
        best = {}
        queue = []
        for node, spent in sources:
            if spent <= limit_s and (node not in best or spent < best[node]):
                best[node] = spent
                heapq.heappush(queue, (spent, node))
        while queue:
            t, i = heapq.heappop(queue)
            if t > best.get(i, math.inf):
                continue
            lo, hi = self.start[i], self.start[i + 1]
            for k in range(lo, hi):
                j = int(self.to[k])
                nxt = t + float(self.cost[k]) / SPEED
                if nxt <= limit_s and nxt < best.get(j, math.inf):
                    best[j] = nxt
                    heapq.heappush(queue, (nxt, j))
        return best


def load(path=CACHE):
    if not path.exists():
        raise FileNotFoundError(
            f"{path} is not there - run `python -m commuterlviv walk` once to "
            "fetch the footpaths from Overpass")
    return Walk.load(path)


def main(argv):
    """`python -m commuterlviv walk [--refresh]` - fetch and compile once."""
    if CACHE.exists() and "--refresh" not in argv:
        w = load()
        print(f"{CACHE} already holds {len(w.lat)} nodes; --refresh to refetch")
        return
    print("asking Overpass for the footpaths - this takes a minute or two")
    raw = fetch()
    print(f"{len(raw['elements'])} elements; compiling")
    save(raw=raw)
    w = load()
    print(f"{CACHE}: {len(w.lat)} nodes, {len(w.to) // 2} edges, "
          f"{CACHE.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":  # pragma: no cover - the CLI entry does this
    import sys
    main(sys.argv[1:])
