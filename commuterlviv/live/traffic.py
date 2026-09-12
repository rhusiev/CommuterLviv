"""How fast the streets are running, where the trams and buses can see them.

The pace model already learns one number per unit of track: the ratio of how
long vehicles are actually taking to how long the timetable expects. Above 1 is
slower than scheduled, which on a street is traffic. This turns that into a map.

A unit belongs to one route's shape, so a street ten routes run down carries ten
units, each with its own number and its own slightly different idea of where the
kerb is. Drawing those as they are gives ten near-parallel lines crossing each
other. They are pooled instead, on the key the model itself pools evidence on:
`Shape.corridor`, a 120 m box of the city crossed on one of eight headings. One
line comes out per piece of street per direction of travel, coloured by the
weighted mean of every unit in it.

The one split kept is tram against road. A tram on its own track is not in the
traffic the cars and buses are in, so trams are pooled apart; a trolleybus is on
the road with the buses and is pooled with them.

Two things are served. The segments - which piece of street each number belongs
to - never change while the service runs, so they go out once and are cached
like the route shapes. The numbers themselves go out on their own, in the same
order, and are small.

A piece of street nothing has crossed lately has no number of its own: the model
backs off to the corridor and then to the city, which is a reasonable ETA and a
meaningless traffic reading. Those segments are sent as null and drawn as
nothing, which is why a street with no transit on it stays grey instead of being
invented.

The ends of a shape are left out altogether. A vehicle at a terminus crawls in,
parks, and crawls out again, and the crawling is rolling time on a cell whose
timetabled pace is short, so the ratio there is high on every route in the city.
That is a layover, not traffic, so `TERMINUS` metres at either end of every
shape are not drawn rather than drawn red. Only that shape's own units go: a
route running past another's terminus still pools its own view of the street.
"""
import json

import numpy as np

from . import geometry

# effective observations behind a line before it is worth drawing; one vehicle
# crossing contributes about one, decaying with the model's fast half-life
CONFIDENCE = 3.0

SIMPLIFY = 12.0     # m a drawn segment may stray from the street

PERIOD = 30.0       # s one reading is served for; the clients ask every 60

TERMINUS = 200.0    # m at either end of a shape whose pace is layover, not traffic

TRAM, ROAD = 0, 1


def segments(net, model):
    """One line per piece of street per direction, with the units it reads.

    The drawn geometry is a run of cells from whichever shape follows the piece
    of street furthest, so it is a real route's own polyline rather than a
    synthetic average of several.
    """
    kinds = _kinds(net)
    drop = _termini(net, model)
    pooled = {}
    for sid in sorted(model.shape_base):
        base = model.shape_base[sid]
        shape = net.shapes[sid]
        cells = model.unit[base:base + shape.cells]
        key_of = shape.corridor
        for lo, hi in _runs(key_of):
            units = {u for u in cells[lo:hi + 1].tolist() if u not in drop}
            if not units:
                continue
            group = pooled.setdefault((int(key_of[lo]), kinds.get(sid, ROAD)),
                                      {"units": set(), "run": None})
            group["units"] |= units
            run = group["run"]
            if run is None or hi - lo > run[2] - run[1]:
                group["run"] = (sid, lo, hi)
    lines, units = [], []
    for key in sorted(pooled):
        group = pooled[key]
        sid, lo, hi = group["run"]
        shape = net.shapes[sid]
        step = shape.length / shape.cells
        # both ends of the run, so a one-cell piece is still a line
        at = np.minimum(np.arange(lo, hi + 2) * step, shape.length)
        lines.append(geometry.points(geometry.simplify(shape.at(at), SIMPLIFY)))
        units.append(sorted(group["units"]))
    return {"lines": lines, "unit": units}


def _kinds(net):
    """TRAM or ROAD, per shape.

    A shape any tram trip runs counts as tram track even if something else uses
    it too, since that is where the tram's own pace was measured.
    """
    out = {}
    for trip, sid in net.trip_shape.items():
        route = net.routes.get(net.trip_route.get(trip))
        if route is not None and sid in net.shapes:
            kind = TRAM if route["type"] == "tram" else ROAD
            out[sid] = min(out.get(sid, kind), kind)
    return out


def _termini(net, model, reach=TERMINUS):
    """The units within `reach` of either end of any shape.

    A unit belongs to one shape - cells are numbered per shape and sections are
    too - so this drops the ends of each shape and nothing else. Where another
    route runs down the same street it has its own units there, and those still
    stand for the street.
    """
    out = set()
    for sid, base in model.shape_base.items():
        shape = net.shapes[sid]
        step = shape.length / shape.cells
        edge = int(min(reach / step, shape.cells / 2.0))
        cells = model.unit[base:base + shape.cells]
        out.update(cells[:edge + 1].tolist())
        out.update(cells[shape.cells - edge - 1:].tolist())
    return out


def _runs(unit):
    """(start, end) cell of each run of equal values, end inclusive."""
    edges = np.flatnonzero(np.diff(unit)) + 1
    starts = np.concatenate(([0], edges))
    ends = np.concatenate((edges - 1, [len(unit) - 1]))
    return zip(starts.tolist(), ends.tolist())


class Pool:
    """Which units stand behind each drawn line, flattened for one pass.

    A reading is a weighted mean per line over 25,625 units in all, which as a
    Python loop over the lines costs more than the rest of the request put
    together. Flat once, `bincount` per reading.
    """

    def __init__(self, groups):
        self.n = len(groups)
        self.owner = np.repeat(np.arange(self.n),
                               [len(g) for g in groups])
        self.flat = np.fromiter((u for g in groups for u in g), np.int64,
                                len(self.owner))


def reading(model, pool, now, floor=CONFIDENCE):
    """The ratio for each line, or None where too little has been seen.

    The weight asked of is the slow layer's, decayed to `now`: it is the one a
    unit's own number is built from, so it answers "has anything driven here
    lately" rather than "does the model have an opinion", which it always does.
    A line's number is its units' ratios weighted by that, so a street a single
    route crawls along and ten run freely reads as the ten.
    """
    slot = model.slot(now)
    pace = model.pace.read(now, slot)[pool.flat]
    weight = model.pace.cs.read(now)[1][pool.flat]
    seen = np.bincount(pool.owner, weight, pool.n)
    total = np.bincount(pool.owner, pace * weight, pool.n)
    ratio = np.where(seen >= floor, total / np.maximum(seen, 1e-9), np.nan)
    return {"t": int(now),
            "ratio": [None if np.isnan(r) else round(float(r), 3)
                      for r in ratio]}


class Cache:
    """One reading per `PERIOD` seconds, serialised once.

    Reading it is a pass over every unit and a JSON array of thousands of
    numbers, while the numbers themselves move on the scale of minutes. Every
    client polling inside the same period therefore gets the same bytes.
    """

    def __init__(self, model, groups, period=PERIOD):
        self.model, self.pool, self.period = model, Pool(groups), period
        self.epoch, self.body = None, b""

    def read(self, now):
        epoch = int(now // self.period)
        if epoch != self.epoch:
            self.epoch = epoch
            self.body = json.dumps(reading(self.model, self.pool, now)).encode()
        return self.body
