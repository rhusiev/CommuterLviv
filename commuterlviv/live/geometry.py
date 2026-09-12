"""Where a route physically goes.

Computed here once so every client draws the same line: the thinned shapes, each
marked with the feed direction it runs, which is what lets a client draw a
two-way stretch as two tracks. All in metres on the projected plane, converted
to degrees only on the way out.
"""
import numpy as np

from .. import network

SIMPLIFY = 8.0       # m a thinned line may stray from the real one


def describe(net, route_ids):
    """Every route's geometry, indexed the way the catalog indexes routes."""
    by_route = {}
    for trip, r in net.trip_route.items():
        sid = net.trip_shape.get(trip)
        if sid in net.shapes:
            by_route.setdefault(r, set()).add((net.trip_dir.get(trip, 0), sid))
    return {"routes": [_route(net, sorted(by_route.get(r, ()))) for r in route_ids]}


def _route(net, pairs):
    return {"lines": [
        {"dir": d, "pts": points(simplify(net.shapes[sid].xy, SIMPLIFY))}
        for d, sid in pairs]}


def points(xy):
    ll = network.to_ll(xy)
    return [[round(float(a), 5), round(float(b), 5)] for a, b in ll]


def simplify(xy, tol):
    """Ramer-Douglas-Peucker, iteratively to keep off the recursion stack."""
    keep = np.zeros(len(xy), bool)
    keep[0] = keep[-1] = True
    todo = [(0, len(xy) - 1)]
    while todo:
        lo, hi = todo.pop()
        if hi - lo < 2:
            continue
        seg = xy[hi] - xy[lo]
        norm = float(np.hypot(*seg))
        rel = xy[lo + 1:hi] - xy[lo]
        # distance to the segment's line, or to the endpoint if it is degenerate
        off = (np.abs(seg[0] * rel[:, 1] - seg[1] * rel[:, 0]) / norm
               if norm > 1e-9 else np.linalg.norm(rel, axis=1))
        i = int(np.argmax(off))
        if off[i] > tol:
            keep[lo + 1 + i] = True
            todo.append((lo, lo + 1 + i))
            todo.append((lo + 1 + i, hi))
    return xy[keep]
