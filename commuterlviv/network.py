"""Route geometry and linear referencing.

Everything downstream works in "distance along the trip's shape", in metres,
rather than in lat/lon. That turns a 2-D tracking problem into a 1-D one and
makes a stop just a scalar position on the line.
"""
import copy
import os
import pickle
from dataclasses import dataclass

import numpy as np

from . import gtfs, overrides

LAT0, LON0 = 49.84, 24.03
KX = gtfs.LAT_M * np.cos(np.radians(LAT0))
KY = gtfs.LAT_M

CACHE = os.path.join(gtfs.DATA, "network.pkl")


@dataclass(frozen=True)
class Geometry:
    """How fine the model's picture of the road is. Nothing else reads this.

    Tracking, the stop positions and therefore the ground truth are all in
    metres along a shape and do not depend on any of these three numbers, so
    two geometries can be scored against each other on identical crossings -
    and `regrid` can change them on an already-built network for the price of
    recomputing three arrays per shape.
    """

    cell: float = 100.0     # speed-field cell length along a shape, metres
    grid: float = 120.0     # size of the shared spatial cell used to pool routes
    octants: int = 8        # heading classes a corridor cell is split into


DEFAULT = Geometry()


def to_xy(lat, lon):
    return np.stack([(np.asarray(lon) - LON0) * KX,
                     (np.asarray(lat) - LAT0) * KY], axis=-1)


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
    ab = b - a
    l2 = np.maximum((ab * ab).sum(1), 1e-9)
    t = np.clip(((p - a) * ab).sum(1) / l2, 0.0, 1.0)
    proj = a + t[:, None] * ab
    d2 = ((proj - p) ** 2).sum(1)
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
        head = self.at(np.minimum(mid + 25.0, self.length)) - \
            self.at(np.maximum(mid - 25.0, 0.0))
        k = 2 * np.pi / geom.octants
        oct_ = np.round(np.arctan2(head[:, 0], head[:, 1]) / k).astype(int) % geom.octants
        gx = np.floor(pts[:, 0] / geom.grid).astype(np.int64)
        gy = np.floor(pts[:, 1] / geom.grid).astype(np.int64)
        self.corridor = (gx * 100003 + gy) * geom.octants + oct_

    def at(self, d):
        """Position at distance d along the line (vectorised)."""
        d = np.clip(np.asarray(d, dtype=float), 0.0, self.length)
        i = np.clip(np.searchsorted(self.cum, d) - 1, 0, len(self.cum) - 2)
        seg = np.maximum(self.cum[i + 1] - self.cum[i], 1e-9)
        f = ((d - self.cum[i]) / seg)[..., None]
        return self.xy[i] + f * (self.xy[i + 1] - self.xy[i])


class Net:
    def __init__(self):
        self.shapes = {}
        self.stops = {}
        self.routes = {}
        self.trip_shape = {}
        self.trip_route = {}
        self.trip_stops = {}        # trip_id -> (stop_ids, dist[], sched_sec[])
        self.pattern_of = {}        # trip_id -> pattern key


def candidates(shape, p, slack=250.0, cap=10):
    """Every plausible place on the shape this point could be: the local minima
    of distance-to-line. A shape that doubles back passes each stop twice."""
    a, b = shape.xy[:-1], shape.xy[1:]
    ab = b - a
    l2 = np.maximum((ab * ab).sum(1), 1e-9)
    t = np.clip(((p - a) * ab).sum(1) / l2, 0.0, 1.0)
    d2 = ((a + t[:, None] * ab - p) ** 2).sum(1)
    if len(d2) == 1:
        loc = np.array([0])
    else:
        pad = np.concatenate([[np.inf], d2, [np.inf]])
        loc = np.nonzero((pad[1:-1] <= pad[:-2]) & (pad[1:-1] <= pad[2:]))[0]
    err = np.sqrt(d2[loc])
    keep = loc[err <= max(err.min(), 1e-9) + min(slack, 400.0)]
    err = np.sqrt(d2[keep])
    order = np.argsort(err)[:cap]
    keep, err = keep[order], err[order]
    dist = shape.cum[keep] + t[keep] * np.sqrt(l2[keep])
    return dist, err


def _stop_dists(shape, stop_xy):
    """Assign each stop a position on the shape: least total lateral error over
    all strictly increasing assignments (Viterbi over the candidate sets)."""
    cands = [candidates(shape, p) for p in stop_xy]
    prev_cost = np.asarray(cands[0][1], dtype=float) + 1e-4 * cands[0][0]
    back = []
    for k in range(1, len(cands)):
        pd, pe = cands[k - 1]
        cd, ce = cands[k]
        ok = cd[:, None] > pd[None, :] + 1.0
        cost = np.where(ok, prev_cost[None, :], np.inf)
        j = np.argmin(cost, axis=1)
        best = cost[np.arange(len(cd)), j]
        dead = ~np.isfinite(best)
        if dead.all():
            j = np.full(len(cd), int(np.argmin(prev_cost)))
            best = prev_cost[j] + 1e3
        elif dead.any():
            best[dead] = np.inf
        back.append(j)
        prev_cost = best + ce + 1e-4 * cd

    idx = [int(np.argmin(prev_cost))]
    for j in reversed(back):
        idx.append(int(j[idx[-1]]))
    idx.reverse()
    out = np.array([cands[k][0][idx[k]] for k in range(len(cands))], dtype=float)
    err = float(max(cands[k][1][idx[k]] for k in range(len(cands))))
    out = np.maximum.accumulate(out + np.arange(len(out)) * 1e-3)
    return out, err


def _sec(hms):
    h, m, s = hms.split(":")
    return int(h) * 3600 + int(m) * 60 + int(s)


def build():
    net = Net()
    pts = {}
    for r in gtfs.table("shapes.txt"):
        pts.setdefault(r["shape_id"], []).append(
            (int(r["shape_pt_sequence"]), float(r["shape_pt_lat"]), float(r["shape_pt_lon"])))
    for sid, rows in pts.items():
        rows.sort()
        arr = np.array([(a[1], a[2]) for a in rows])
        net.shapes[sid] = Shape(to_xy(arr[:, 0], arr[:, 1]))

    for s in gtfs.table("stops.txt"):
        net.stops[s["stop_id"]] = {
            "name": s["stop_name"], "code": s["stop_code"],
            "lat": float(s["stop_lat"]), "lon": float(s["stop_lon"]),
            "desc": s["stop_desc"]}
    for r in gtfs.table("routes.txt"):
        net.routes[r["route_id"]] = {
            "short": r["route_short_name"], "long": r["route_long_name"],
            "type": gtfs.vehicle_type(r["route_short_name"])}

    for t in gtfs.table("trips.txt"):
        net.trip_shape[t["trip_id"]] = t["shape_id"]
        net.trip_route[t["trip_id"]] = t["route_id"]

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
    return net


def fresh():
    """Whether the cached geometry was built from the static feed we now have,
    and from the overrides as they read now: editing them has to rebuild, or
    the edit would take effect at some unrelated later feed change."""
    if not os.path.exists(CACHE) or not os.path.exists(gtfs.ZIP):
        return False
    newest = max(os.path.getmtime(gtfs.ZIP),
                 os.path.getmtime(overrides.PATH)
                 if os.path.exists(overrides.PATH) else 0.0)
    return os.path.getmtime(CACHE) >= newest


def regrid(net, geom):
    """The same network, re-celled. Only `Shape` depends on the geometry, and
    the stop assignment that dominates a build does not, so a sweep over the
    three numbers pays for the build once."""
    out = copy.copy(net)
    out.shapes = {sid: Shape(s.xy, geom) for sid, s in net.shapes.items()}
    return out


def load(rebuild=False, geom=DEFAULT):
    net = _load(rebuild)
    return net if geom == DEFAULT else regrid(net, geom)


def _load(rebuild):
    gtfs.static_zip()   # so a feed that changed overnight invalidates the cache
    if not rebuild and fresh():
        with open(CACHE, "rb") as f:
            return pickle.load(f)
    net = build()
    tmp = CACHE + ".tmp"
    with open(tmp, "wb") as f:
        pickle.dump(net, f, pickle.HIGHEST_PROTOCOL)
    os.replace(tmp, CACHE)
    return net
