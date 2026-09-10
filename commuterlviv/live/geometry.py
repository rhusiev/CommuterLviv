"""Where a route physically goes, and which way along it traffic runs.

The clients draw a route as a coloured line with arrowheads sitting on it. Both
of them draw the same line, because the line is computed here once and sent as
numbers: a browser and a phone that each did their own geometry would disagree
about which stretches are two-way, and that disagreement is exactly the thing a
rider would notice.

Three things are worked out, all in metres on the projected plane and converted
to degrees only on the way out:

  lines    the shapes the route's trips follow, thinned for the wire
  arrows   a heading every `SPACING` metres along each shape
  two-way  an arrow that has an opposite-running arrow on top of it

The feed gives a route several shapes - one per direction, sometimes more for
short workings - and says which direction each trip runs with `direction_id`.
Where the outbound and inbound shapes lie on the same street, both carry arrows
in opposite directions a few metres apart, which would draw as a mess. One of
each such pair is dropped and the survivor is marked two-way, so the client
draws one double-headed arrow there instead of two fighting single ones.

Static for the process's life, so `app.py` builds it once and serves it against
an ETag, like the catalog.
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
    """A position and a compass heading every `SPACING` metres along one shape.

    The heading is the chord over `SPAN` metres either side rather than the
    tangent, so a single kinked point in the feed's polyline cannot spin an
    arrowhead round.
    """
    n = int(shape.length // SPACING)
    if n < 1:
        return np.zeros((0, 2)), np.zeros(0)
    at = (np.arange(n) + 0.5) * (shape.length / n)
    step = (shape.at(np.minimum(at + SPAN, shape.length))
            - shape.at(np.maximum(at - SPAN, 0.0)))
    return shape.at(at), np.degrees(np.arctan2(step[:, 0], step[:, 1])) % 360.0


def _thin(shapes, geom):
    """One arrow per stretch of street, marked two-way where the route also
    runs the other way along it.

    A route has two to five shapes and they overlap heavily: the two directions
    share most streets, and a short working repeats the trunk a third time. Kept
    naively that draws three arrows on top of each other. So an arrow is dropped
    when a kept one within `NEAR` already points the same way.

    Whether a stretch is two-way is asked of the *shapes*, not of the other
    arrows. Arrows are spaced along each shape independently, so two of them on
    the same street can be a hundred metres apart and never meet; the shape that
    carries them is continuous and always answers.

    Greedy and quadratic over the ~200 arrows of one route, and each of those
    projected onto its four-or-fewer sibling shapes. A spatial index would be
    faster and would have to be kept correct; this does not.
    """
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
    """`[lat, lon, heading, two-way]`, a list rather than an object because a
    route carries a couple of hundred of these and the keys would outweigh
    them."""
    return [[*_points([p])[0], int(round(h)) % 360, int(t)] for p, h, t in arrows]


def _simplify(xy, tol):
    """Ramer-Douglas-Peucker, iteratively: a shape of 700 points recursed on
    itself deep enough to matter, and the stack is the only reason to recurse."""
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
        # Distance to the segment's line, or to the endpoint if it is a point
        off = (np.abs(seg[0] * rel[:, 1] - seg[1] * rel[:, 0]) / norm
               if norm > 1e-9 else np.linalg.norm(rel, axis=1))
        i = int(np.argmax(off))
        if off[i] > tol:
            keep[lo + 1 + i] = True
            todo.append((lo, lo + 1 + i))
            todo.append((lo + 1 + i, hi))
    return xy[keep]
