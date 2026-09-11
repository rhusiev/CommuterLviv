"""Where a route physically goes, and which way along it traffic runs.

Computed here once so every client draws the same line: the thinned shapes, an
arrowhead every `SPACING` metres, and a two-way flag where the route also runs
the other way along the same stretch. All in metres on the projected plane,
converted to degrees only on the way out.
"""
import numpy as np

from .. import network

SIMPLIFY = 8.0       # m a thinned line may stray from the real one
SPACING = 220.0      # m between arrowheads along a shape
SPAN = 25.0          # m either side of an arrow the heading averages over
NEAR = 35.0          # m within which two arrows are on the same stretch
OPPOSED = 40.0       # degrees off head-on that still counts as opposite


def describe(net, route_ids):
    """Every route's geometry, indexed the way the catalog indexes routes."""
    by_route = {}
    for trip, r in net.trip_route.items():
        sid = net.trip_shape.get(trip)
        if sid in net.shapes:
            by_route.setdefault(r, set()).add((net.trip_dir.get(trip, 0), sid))
    return {"routes": [_route(net, sorted(by_route.get(r, ()))) for r in route_ids]}


def _route(net, pairs):
    lines, arrows = [], []
    for d, sid in pairs:
        shape = net.shapes[sid]
        lines.append({"dir": d, "pts": _points(_simplify(shape.xy, SIMPLIFY))})
        arrows.append((sid, *_arrows(shape)))
    return {"lines": lines,
            "arrows": _thin(arrows, {sid: net.shapes[sid] for _, sid in pairs})}


def _arrows(shape):
    """A position and heading every `SPACING` metres along one shape; the
    heading is the chord over `SPAN` metres either side, not the tangent, so
    one kinked point in the feed's polyline cannot spin an arrowhead round."""
    n = int(shape.length // SPACING)
    if n < 1:
        return np.zeros((0, 2)), np.zeros(0)
    at = (np.arange(n) + 0.5) * (shape.length / n)
    step = (shape.at(np.minimum(at + SPAN, shape.length))
            - shape.at(np.maximum(at - SPAN, 0.0)))
    return shape.at(at), np.degrees(np.arctan2(step[:, 0], step[:, 1])) % 360.0


def _thin(shapes, geom):
    """One arrow per stretch of street, marked two-way where the route also
    runs the other way along it; an arrow within `NEAR` of a kept one pointing
    the same way is dropped. Two-wayness is asked of the sibling *shapes*, not
    of the other arrows, since two arrows on the same street may never meet."""
    out = []
    for sid, at, head in shapes:
        others = [s for i, s in geom.items() if i != sid]
        for p, h in zip(at, head):
            if any(abs((h - kept[1] + 180.0) % 360.0 - 180.0) <= OPPOSED
                   and np.hypot(*(p - kept[0])) <= NEAR for kept in out):
                continue
            out.append([p, h, any(_opposed(s, p, h) for s in others)])
    return _wire(out)


def _opposed(shape, p, h):
    """Whether this shape passes within `NEAR` of the point, running back the
    other way."""
    d, off = network.project(shape.xy, shape.cum, p)
    if off > NEAR:
        return False
    step = (shape.at(min(d + SPAN, shape.length)) - shape.at(max(d - SPAN, 0.0)))
    there = np.degrees(np.arctan2(step[0], step[1])) % 360.0
    return abs((h - there + 180.0) % 360.0 - 180.0) >= 180.0 - OPPOSED


def _points(xy):
    ll = network.to_ll(xy)
    return [[round(float(a), 5), round(float(b), 5)] for a, b in ll]


def _wire(arrows):
    """`[lat, lon, heading, two-way]`, as a list: a route carries hundreds and
    the keys would outweigh the values."""
    return [[*_points([p])[0], int(round(h)) % 360, int(t)] for p, h, t in arrows]


def _simplify(xy, tol):
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
