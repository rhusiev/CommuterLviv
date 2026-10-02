"""The city on foot: an OpenStreetMap footpath graph, and shortest walks on it.

Fetched from Overpass and cached in `data/walk.npz`, with every node's
elevation from the Terrarium tiles so a slope is walked slower up than down.
`renew` refetches it beside the one held - the service monthly, at night, and
`python -m commuterlviv walk --refresh` on demand - so no served request ever
waits on an external API. Knows nothing about timetables -
it answers only how many seconds of walking lie between points.
"""
import copy
import hashlib
import io
import math
import time
from pathlib import Path
from typing import NamedTuple

import numpy as np
import requests
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import dijkstra

from . import network

DATA = Path(__file__).resolve().parent.parent / "data"
CACHE = DATA / "walk.npz"

OVERPASS = "https://overpass-api.de/api/interpreter"

# Mapzen's terrain on AWS: metres are R * 256 + G + B / 256 - 32768. Zoom 13 is
# a pixel per 12 m here, finer than the 30 m survey under it.
TERRARIUM = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"
ZOOM = 13

# Overpass answers 406 to a POST with no User-Agent
AGENT = "commuterlviv/1.0 (+https://github.com/rad1an/commuterlviv)"

SPEED = 1.25    # m/s on the level, unhurried; the graph models no crossings or kerbs

# rise over run past which the terrain model is more likely wrong than the hill
# steep: a bridge or a cutting the 30 m survey does not see
STEEPEST = 0.3

# ways somebody on foot may use; motorways and their links are not walkable
WALKABLE = {
    "footway", "path", "pedestrian", "steps", "living_street", "residential",
    "service", "unclassified", "tertiary", "secondary", "primary",
    "tertiary_link", "secondary_link", "primary_link", "track", "road",
    "crossing", "corridor",
}

MARGIN = 0.02   # degrees around the stops' bounding box, about 2 km


def query(bbox):
    """The Overpass query for one bounding box; `>` pulls the nodes in too."""
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
    """The raw Overpass answer. Minutes, and rate limited: call it by hand."""
    net = net or network.load()
    get = session or requests
    res = get.post(OVERPASS, data={"data": query(bbox(net))}, timeout=600,
                   headers={"User-Agent": AGENT})
    res.raise_for_status()
    return res.json()


def elevation(lat, lon, session=None):
    """Metres above the sea at each point, bilinear between the pixels of the
    Terrarium tiles around them; a minute of downloads for the city."""
    from PIL import Image

    get = session or requests
    n = 256 * 2 ** ZOOM
    x = (np.asarray(lon) + 180.0) / 360.0 * n - 0.5
    y = (1.0 - np.arcsinh(np.tan(np.radians(lat))) / math.pi) / 2.0 * n - 0.5
    x0, y0 = int(x.min()) // 256, int(y.min()) // 256
    x1, y1 = int(x.max() + 1) // 256, int(y.max() + 1) // 256
    tiles = [[None] * (x1 - x0 + 1) for _ in range(y1 - y0 + 1)]
    for ty in range(y0, y1 + 1):
        for tx in range(x0, x1 + 1):
            res = get.get(TERRARIUM.format(z=ZOOM, x=tx, y=ty), timeout=60,
                          headers={"User-Agent": AGENT})
            res.raise_for_status()
            rgb = np.asarray(Image.open(io.BytesIO(res.content)).convert("RGB"),
                             dtype=np.float64)
            tiles[ty - y0][tx - x0] = rgb @ (256.0, 1.0, 1 / 256) - 32768.0
    z = np.block(tiles)
    x, y = x - 256 * x0, y - 256 * y0
    i, j = np.floor(y).astype(int), np.floor(x).astype(int)
    fy, fx = y - i, x - j
    return ((z[i, j] * (1 - fx) + z[i, j + 1] * fx) * (1 - fy) +
            (z[i + 1, j] * (1 - fx) + z[i + 1, j + 1] * fx) * fy
            ).astype(np.float32)


def hill(rise, run):
    """How many times as fast as on the level a slope is walked: Tobler's
    hiking function (1993) over its value on the flat, so 1.19 at its fastest,
    a 5% descent, and 0.70 up 10%."""
    s = np.clip(rise / np.maximum(run, 1.0), -STEEPEST, STEEPEST)
    return np.exp(-3.5 * (np.abs(s + 0.05) - 0.05))


def metres(lat1, lon1, lat2, lon2):
    """Equirectangular distance, exact enough over a city block."""
    k = math.cos(math.radians((lat1 + lat2) / 2))
    return math.hypot((lat2 - lat1) * 111320.0, (lon2 - lon1) * 111320.0 * k)


def compile_graph(raw):
    """Overpass JSON into the arrays `Walk` runs on; edges are undirected,
    since one-way streets are one-way only for traffic."""
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
    # sorted by tail so a node's neighbours are one contiguous slice
    a = np.array(heads + tails, dtype=np.int32)
    b = np.array(tails + heads, dtype=np.int32)
    w = np.array(costs + costs, dtype=np.float32)
    order = np.argsort(a, kind="stable")
    a, b, w = a[order], b[order], w[order]
    start = np.searchsorted(a, np.arange(len(lat) + 1)).astype(np.int64)
    return lat, lon, b, w, start


def save(path=CACHE, raw=None):
    """The graph, without the elevation `climb` adds."""
    raw = raw or fetch()
    lat, lon, to, w, start = compile_graph(raw)
    path.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(path, lat=lat, lon=lon, to=to, cost=w, start=start,
                        built=np.array([time.time()]))
    return path


def renew(path=CACHE, keep=0.9):
    """Refetches the graph and its heights beside the one held, then swaps it
    in. One with under `keep` of the nodes held is refused: that is Overpass
    cut short, not the city shrinking."""
    fresh = path.with_name("walk.next.npz")
    try:
        save(fresh)
        climb(fresh)
        if path.exists():
            with np.load(fresh) as a, np.load(path) as b:
                got, held = len(a["lat"]), len(b["lat"])
            if got < keep * held:
                raise ValueError(f"Overpass gave {got} footpath nodes, "
                                 f"against {held} held")
        fresh.replace(path)
    finally:
        fresh.unlink(missing_ok=True)


def age(path=CACHE):
    """Seconds since the graph was fetched; one saved before that was noted
    is as old as its file."""
    with np.load(path) as z:
        built = float(z["built"][0]) if "built" in z.files else \
            path.stat().st_mtime
    return time.time() - built


def climbed(path=CACHE):
    with np.load(path) as z:
        return "ele" in z.files


def climb(path=CACHE, session=None):
    """Adds each node's elevation to a saved graph."""
    with np.load(path) as z:
        arrays = dict(z)
    arrays["ele"] = elevation(arrays["lat"], arrays["lon"], session)
    np.savez_compressed(path, **arrays)


class Spot(NamedTuple):
    """Where a point steps onto the footpaths: (`lat`, `lon`), `t` of the way
    along the edge from node `u` to node `v` that `edge` seconds walk, `off`
    seconds of walking from the point."""
    lat: float
    lon: float
    u: int
    v: int
    t: float
    edge: float
    off: float

    def ends(self):
        """Each end of the edge, with the seconds walked to it from the point."""
        return [(self.u, self.off + self.edge * self.t),
                (self.v, self.off + self.edge * (1 - self.t))]

    def along(self, other):
        """Seconds from this spot's point to the other's along their shared
        edge, which the graph cannot see, or inf if they are on different ones."""
        if {self.u, self.v} != {other.u, other.v}:
            return math.inf
        t = other.t if other.u == self.u else 1 - other.t
        return self.off + other.off + self.edge * abs(self.t - t)


class Walk:
    """A footpath graph, and the walks that start anywhere on it."""

    def __init__(self, lat, lon, to, cost, start, ele=None):
        self.lat, self.lon = lat, lon
        self.to, self.cost, self.start = to, cost, start
        self.secs = cost.astype(float) / SPEED
        if ele is not None:
            tail = np.repeat(np.arange(len(lat)), np.diff(start))
            self.secs /= hill(ele[to].astype(float) - ele[tail], cost)
        # what a walking time rests on, for a table of them to be checked against
        self.model = f"{SPEED} m/s, " + ("Tobler slopes" if ele is not None
                                         else "level")
        # and which footpaths it was walked on
        h = hashlib.blake2b(digest_size=16)
        for a in (lat, lon, to, cost, start, *(() if ele is None else (ele,))):
            h.update(np.ascontiguousarray(a).tobytes())
        self.graph = h.hexdigest()
        self.pace = 1.0
        self.cell = 0.002   # degrees, about 200 m per grid cell
        self.grid = {}
        for i, (a, o) in enumerate(zip(lat, lon)):
            self.grid.setdefault((int(a / self.cell), int(o / self.cell)),
                                 []).append(i)

    @classmethod
    def load(cls, path=CACHE):
        with np.load(path) as z:
            return cls(z["lat"], z["lon"], z["to"], z["cost"], z["start"],
                       z["ele"] if "ele" in z.files else None)

    def paced(self, pace):
        """The graph for somebody walking `pace` times as long."""
        out = copy.copy(self)
        out.secs, out.pace = self.secs * pace, self.pace * pace
        return out

    def flat(self, metres):
        """Seconds to walk `metres` on the level."""
        return metres / SPEED * self.pace

    def near(self, lat, lon, within=150.0):
        """Every node within `within` metres, nearest first; empty means the
        point is off the graph."""
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

    def attach(self, lat, lon, within=150.0):
        """The nearest point on any edge of a node within `within` metres, or
        None off the graph. Only that one, and straight to it: joining a point
        to every node in reach would let a walk cut across the block to any of
        them."""
        near = np.array([i for _, i in self.near(lat, lon, within)], dtype=np.int64)
        if not len(near):
            return None
        e = np.concatenate([np.arange(self.start[i], self.start[i + 1]) for i in near])
        u, v = np.repeat(near, np.diff(self.start)[near]), self.to[e]
        k = 111320.0 * math.cos(math.radians(lat))
        ux, uy = (self.lon[u] - lon) * k, (self.lat[u] - lat) * 111320.0
        dx, dy = (self.lon[v] - lon) * k - ux, (self.lat[v] - lat) * 111320.0 - uy
        t = np.clip(-(ux * dx + uy * dy) / np.maximum(dx * dx + dy * dy, 1e-9), 0, 1)
        j = int(np.argmin(np.hypot(ux + t * dx, uy + t * dy)))
        a, b, f = int(u[j]), int(v[j]), float(t[j])
        at = (float(self.lat[a] + f * (self.lat[b] - self.lat[a])),
              float(self.lon[a] + f * (self.lon[b] - self.lon[a])))
        return Spot(*at, a, b, f, float(self.secs[e[j]]),
                    self.flat(metres(lat, lon, *at)))

    def reach(self, sources, limit_s, prev=False):
        """Seconds of walking from the nearest source to every node, inf past
        `limit_s`. `sources` are `(node, seconds already spent)`. With `prev`,
        also each node's predecessor on its shortest walk, out of range at a
        source and where no walk reaches."""
        head = {}
        for node, spent in sources:
            head[node] = min(spent, head.get(node, math.inf))
        n = len(self.lat)
        # one extra node with an edge to each source, as long as the walk
        # already spent getting there, starts them all in one search
        graph = csr_matrix(
            (np.append(self.secs, list(head.values())),
             np.append(self.to, list(head)),
             np.append(self.start, self.start[-1] + len(head))),
            shape=(n + 1, n + 1))
        out = dijkstra(graph, indices=n, limit=limit_s,
                       return_predecessors=prev)
        return (out[0][:n], out[1][:n]) if prev else out[:n]

    def path(self, a, b, limit_s):
        """The footpath from `a` to `b` (both (lat, lon)) as (lat, lon) points,
        or just the two ends when no walk within `limit_s` joins them."""
        sa, sb = self.attach(*a), self.attach(*b)
        if sa is None or sb is None:
            return [a, b]
        best, prev = self.reach(sa.ends(), limit_s, prev=True)
        t, end = min((best[i] + s, i) for i, s in sb.ends())
        direct = sa.along(sb)
        if min(direct, t) == math.inf:
            return [a, b]
        if direct <= t:
            return [a, sa[:2], sb[:2], b]
        nodes = [end]
        while 0 <= (node := prev[nodes[-1]]) < len(self.lat):
            nodes.append(node)
        return [a, sa[:2], *((float(self.lat[i]), float(self.lon[i]))
                             for i in reversed(nodes)), sb[:2], b]


def load(path=CACHE):
    if not path.exists():
        raise FileNotFoundError(
            f"{path} is not there - run `python -m commuterlviv walk` once to "
            "fetch the footpaths from Overpass")
    return Walk.load(path)


def main(argv):
    """`python -m commuterlviv walk [--refresh]` - fetch and compile once."""
    if "--refresh" in argv or not CACHE.exists():
        print("asking Overpass for the footpaths, then the elevation of every "
              "node - a few minutes")
        renew()
    elif climbed():
        print(f"{CACHE} already holds {len(load().lat)} nodes; --refresh to "
              "refetch")
        return
    else:
        print("fetching the elevation of every node")
        climb()
    w = load()
    print(f"{CACHE}: {len(w.lat)} nodes, {len(w.to) // 2} edges, "
          f"{CACHE.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":  # pragma: no cover - the CLI entry does this
    import sys
    main(sys.argv[1:])
