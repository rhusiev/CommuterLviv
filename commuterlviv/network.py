"""Route geometry and linear referencing: everything downstream works in metres
along the trip's shape rather than in lat/lon."""
import copy
import hashlib
import os
import pickle
from dataclasses import dataclass

import numpy as np

from . import files, gtfs, overrides

LAT0, LON0 = 49.84, 24.03
KX = gtfs.LAT_M * np.cos(np.radians(LAT0))
KY = gtfs.LAT_M

CACHE = os.path.join(gtfs.DATA, "network.pkl")

EPS = 1e-9              # m (or m²) a length is floored at, so none divides by zero
HEADING_SPAN = 25.0     # m either side of a cell's middle its heading is read over
GRID_ROW = 100003       # more grid cells than the city spans: (gx, gy) as one id

# the stop placement's costs, in metres of lateral error
EARLIER = 1e-4          # per metre along: of two places as close, the earlier
STOP_GAP = 1.0          # m a stop must lie past the one before it
OUT_OF_ORDER = 1e3      # for a stop with no place past the one before it
STOP_SPREAD = 1e-3      # m between stops placed at one point, to keep them in order
SLACK = 250.0           # m farther than the closest a point's other places may lie
SLACK_MAX = 400.0       # m of slack however much a caller asks for
CANDIDATES = 10         # places kept per point, closest first


@dataclass(frozen=True)
class Geometry:
    """How fine the model's picture of the road is; only `Shape` reads it."""

    cell: float = 50.0      # speed-field cell length along a shape, metres
    grid: float = 120.0     # size of the shared spatial cell used to pool routes
    octants: int = 8        # heading classes a corridor cell is split into


DEFAULT = Geometry()


def to_xy(lat, lon):
    return np.stack([(np.asarray(lon) - LON0) * KX,
                     (np.asarray(lat) - LAT0) * KY], axis=-1)


def to_ll(xy):
    """The inverse of `to_xy`."""
    xy = np.asarray(xy, dtype=float)
    return np.stack([xy[..., 1] / KY + LAT0, xy[..., 0] / KX + LON0], axis=-1)


def _to_segments(a, b, p):
    """Where `p` falls on each segment a-b: the fraction along it, clamped to
    the segment, the segment's squared length, and the squared distance."""
    ab = b - a
    l2 = np.maximum((ab * ab).sum(1), EPS)
    t = np.clip(((p - a) * ab).sum(1) / l2, 0.0, 1.0)
    d2 = ((a + t[:, None] * ab - p) ** 2).sum(1)
    return t, l2, d2


def project(xy, cum, p, lo=None, hi=None):
    """Nearest point on a polyline. Returns (distance along, lateral offset)."""
    a, b = xy[:-1], xy[1:]
    if lo is not None:
        i0 = max(0, int(np.searchsorted(cum, lo) - 1))
        i1 = min(len(a), int(np.searchsorted(cum, hi) + 1))
        if i1 - i0 < 1:
            i0, i1 = 0, len(a)
        a, b = a[i0:i1], b[i0:i1]
        base = i0
    else:
        base = 0
    t, l2, d2 = _to_segments(a, b, p)
    i = int(np.argmin(d2))
    return cum[base + i] + t[i] * np.sqrt(l2[i]), float(np.sqrt(d2[i]))


class Shape:
    __slots__ = ("xy", "cum", "length", "cells", "corridor")

    def __init__(self, xy, geom=DEFAULT):
        self.xy = xy
        step = np.sqrt(((xy[1:] - xy[:-1]) ** 2).sum(1))
        self.cum = np.concatenate([[0.0], np.cumsum(step)])
        self.length = float(self.cum[-1])
        n = max(1, int(np.ceil(self.length / geom.cell)))
        self.cells = n
        mid = (np.arange(n) + 0.5) * (self.length / n)
        pts = self.at(mid)
        head = self.at(np.minimum(mid + HEADING_SPAN, self.length)) - \
            self.at(np.maximum(mid - HEADING_SPAN, 0.0))
        k = 2 * np.pi / geom.octants
        oct_ = np.round(np.arctan2(head[:, 0], head[:, 1]) / k).astype(int) % geom.octants
        gx = np.floor(pts[:, 0] / geom.grid).astype(np.int64)
        gy = np.floor(pts[:, 1] / geom.grid).astype(np.int64)
        self.corridor = (gx * GRID_ROW + gy) * geom.octants + oct_

    def at(self, d):
        """Position at distance d along the line (vectorised)."""
        d = np.clip(np.asarray(d, dtype=float), 0.0, self.length)
        i = np.clip(np.searchsorted(self.cum, d) - 1, 0, len(self.cum) - 2)
        seg = np.maximum(self.cum[i + 1] - self.cum[i], EPS)
        f = ((d - self.cum[i]) / seg)[..., None]
        return self.xy[i] + f * (self.xy[i + 1] - self.xy[i])


class Net:
    # bump when a field is added or its meaning changes: the cache is keyed by
    # the feed alone, so an older one would otherwise load with fields missing
    VERSION = 5

    def __init__(self):
        self.version = self.VERSION
        self.source = ""            # `source()` of what it was built from
        self.shapes = {}
        self.stops = {}
        self.routes = {}
        self.trip_shape = {}
        self.trip_route = {}
        self.trip_dir = {}          # trip_id -> 0 or 1, the feed's direction_id
        self.trip_service = {}      # trip_id -> the feed's service_id
        self.calendar = gtfs.Calendar()     # which services run on a date
        self.trip_stops = {}        # trip_id -> (stop_ids, dist[], sched_sec[])
        self.pattern_of = {}        # trip_id -> pattern key
        self.trip_next = {}         # trip_id -> the block's next trip, same vehicle


def candidates(shape, p, slack=SLACK, cap=CANDIDATES):
    """Every plausible place on the shape this point could be: the local minima
    of distance-to-line. A shape that doubles back passes each stop twice."""
    t, l2, d2 = _to_segments(shape.xy[:-1], shape.xy[1:], p)
    if len(d2) == 1:
        loc = np.array([0])
    else:
        pad = np.concatenate([[np.inf], d2, [np.inf]])
        loc = np.nonzero((pad[1:-1] <= pad[:-2]) & (pad[1:-1] <= pad[2:]))[0]
    err = np.sqrt(d2[loc])
    keep = loc[err <= max(err.min(), EPS) + min(slack, SLACK_MAX)]
    err = np.sqrt(d2[keep])
    order = np.argsort(err)[:cap]
    keep, err = keep[order], err[order]
    dist = shape.cum[keep] + t[keep] * np.sqrt(l2[keep])
    return dist, err


def _stop_dists(shape, stop_xy):
    """Assign each stop a position on the shape: least total lateral error over
    all strictly increasing assignments (Viterbi over the candidate sets)."""
    cands = [candidates(shape, p) for p in stop_xy]
    prev_cost = np.asarray(cands[0][1], dtype=float) + EARLIER * cands[0][0]
    back = []
    for k in range(1, len(cands)):
        pd, pe = cands[k - 1]
        cd, ce = cands[k]
        ok = cd[:, None] > pd[None, :] + STOP_GAP
        cost = np.where(ok, prev_cost[None, :], np.inf)
        j = np.argmin(cost, axis=1)
        best = cost[np.arange(len(cd)), j]
        dead = ~np.isfinite(best)
        if dead.all():
            j = np.full(len(cd), int(np.argmin(prev_cost)))
            best = prev_cost[j] + OUT_OF_ORDER
        elif dead.any():
            best[dead] = np.inf
        back.append(j)
        prev_cost = best + ce + EARLIER * cd

    idx = [int(np.argmin(prev_cost))]
    for j in reversed(back):
        idx.append(int(j[idx[-1]]))
    idx.reverse()
    out = np.array([cands[k][0][idx[k]] for k in range(len(cands))], dtype=float)
    err = float(max(cands[k][1][idx[k]] for k in range(len(cands))))
    out = np.maximum.accumulate(out + np.arange(len(out)) * STOP_SPREAD)
    return out, err


def _sec(hms):
    h, m, s = hms.split(":")
    return int(h) * 3600 + int(m) * 60 + int(s)


def build():
    net = Net()
    _read_shapes(net)
    _read_stops_and_routes(net)
    blocks = _read_trips(net)
    net.calendar = gtfs.Calendar.read()
    _solve_patterns(net)
    for trips in blocks.values():
        trips = sorted((t for t in trips if t in net.trip_stops),
                       key=lambda t: net.trip_stops[t][2][0])
        net.trip_next.update(zip(trips, trips[1:]))
    return net


def _read_shapes(net):
    pts = {}
    for r in gtfs.table("shapes.txt"):
        pts.setdefault(r["shape_id"], []).append(
            (int(r["shape_pt_sequence"]), float(r["shape_pt_lat"]), float(r["shape_pt_lon"])))
    for sid, rows in pts.items():
        rows.sort()
        arr = np.array([(a[1], a[2]) for a in rows])
        net.shapes[sid] = Shape(to_xy(arr[:, 0], arr[:, 1]))


def _read_stops_and_routes(net):
    for s in gtfs.table("stops.txt"):
        net.stops[s["stop_id"]] = {
            "name": s["stop_name"], "code": s["stop_code"],
            "lat": float(s["stop_lat"]), "lon": float(s["stop_lon"]),
            "desc": s["stop_desc"]}
    for r in gtfs.table("routes.txt"):
        net.routes[r["route_id"]] = {
            "short": r["route_short_name"], "long": r["route_long_name"],
            "type": gtfs.vehicle_type(r["route_short_name"])}


def _read_trips(net):
    """Fills in each trip's shape, route, direction and service; the trips of
    each block."""
    blocks = {}
    for t in gtfs.table("trips.txt"):
        if t.get("block_id"):
            blocks.setdefault(t["block_id"], []).append(t["trip_id"])
        net.trip_shape[t["trip_id"]] = t["shape_id"]
        net.trip_route[t["trip_id"]] = t["route_id"]
        net.trip_dir[t["trip_id"]] = int(t["direction_id"] or 0)
        net.trip_service[t["trip_id"]] = t["service_id"]
    return blocks


def _solve_patterns(net):
    """Places each trip's stops along its shape, with the overrides applied."""
    seq = {}
    for r in gtfs.table("stop_times.txt"):
        seq.setdefault(r["trip_id"], []).append(
            (int(r["stop_sequence"]), r["stop_id"], _sec(r["arrival_time"])))

    # Trips sharing a shape and a stop list have identical geometry: solve once.
    solved = {}
    extra = overrides.Overrides.load()
    for trip, rows in seq.items():
        rows.sort()
        sid = net.trip_shape.get(trip)
        if not sid or sid not in net.shapes:
            continue
        ids, when = extra.patch(net, net.trip_route.get(trip), sid,
                                tuple(r[1] for r in rows), [r[2] for r in rows])
        key = (sid, ids)
        if key not in solved:
            shape = net.shapes[sid]
            xy = to_xy(np.array([net.stops[i]["lat"] for i in ids]),
                       np.array([net.stops[i]["lon"] for i in ids]))
            solved[key] = _stop_dists(shape, xy)[0]
        net.pattern_of[trip] = key
        net.trip_stops[trip] = (ids, solved[key], np.array(when, dtype=float))
    extra.report()


def source():
    """A digest of what the network is built from: the feed and the overrides."""
    h = hashlib.blake2b(digest_size=16)
    for path in (gtfs.ZIP, overrides.PATH):
        if os.path.exists(path):
            with open(path, "rb") as f:
                h.update(f.read())
    return h.hexdigest()


def regrid(net, geom):
    """The same network, re-celled: only `Shape` depends on the geometry."""
    out = copy.copy(net)
    out.shapes = {sid: Shape(s.xy, geom) for sid, s in net.shapes.items()}
    return out


def load(rebuild=False, geom=DEFAULT):
    net = _load(rebuild)
    return net if geom == DEFAULT else regrid(net, geom)


def _load(rebuild):
    gtfs.static_zip()   # fetched first when there is none, so `source` hashes it
    src = source()
    if not rebuild and os.path.exists(CACHE):
        with open(CACHE, "rb") as f:
            net = pickle.load(f)
        if (getattr(net, "version", 0) == Net.VERSION
                and getattr(net, "source", None) == src):
            return net
    net = build()
    net.source = src
    with files.replacing(CACHE) as fresh, open(fresh, "wb") as f:
        pickle.dump(net, f, pickle.HIGHEST_PROTOCOL)
    return net
