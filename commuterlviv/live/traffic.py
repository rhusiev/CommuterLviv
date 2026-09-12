"""How fast the streets are running, where the trams and buses can see them.

The pace model already learns one number per unit of track: the ratio of how
long vehicles are actually taking to how long the timetable expects. Above 1 is
slower than scheduled, which on a street is traffic. This turns that into a map.

Two things are served. The segments - which piece of street each number belongs
to - never change while the service runs, so they go out once and are cached
like the route shapes. The numbers themselves go out on their own, in the same
order, and are small.

A unit nothing has crossed lately has no number of its own: the model backs off
to the corridor and then to the city, which is a reasonable ETA and a
meaningless traffic reading. Those segments are sent as null and drawn as
nothing, which is why a street with no transit on it stays grey instead of
being invented.

The ends of a shape are left out altogether. A vehicle at a terminus crawls in,
parks, and crawls out again, and the crawling is rolling time on a cell whose
timetabled pace is short, so the ratio there is high on every route in the city.
That is a layover, not traffic, so `TERMINUS` metres at either end of every
shape are not drawn rather than drawn red.
"""
import json

import numpy as np

from . import geometry

# effective observations on a unit before its number is worth drawing; one
# vehicle crossing contributes about one, decaying with the model's fast half-life
CONFIDENCE = 3.0

SIMPLIFY = 12.0     # m a drawn segment may stray from the street

PERIOD = 30.0       # s one reading is served for; the clients ask every 60

TERMINUS = 200.0    # m at either end of a shape whose pace is layover, not traffic


def segments(net, model):
    """Every run of cells sharing a unit, as a polyline, with the unit it reads.

    Cells are consecutive along a shape and units are runs of them, so a unit's
    geometry is a slice of one shape's polyline - no stitching, and the drawn
    line is the street the number was measured on.
    """
    lines, units = [], []
    # the termini count as already drawn, so nothing is emitted for them
    seen = _termini(net, model)
    for sid, base in model.shape_base.items():
        shape = net.shapes[sid]
        step = shape.length / shape.cells
        cell_unit = model.unit[base:base + shape.cells]
        for lo, hi in _runs(cell_unit):
            unit = int(cell_unit[lo])
            if unit in seen:
                continue
            seen.add(unit)
            # both ends of the run, so a one-cell unit is still a line
            at = np.minimum(np.arange(lo, hi + 2) * step, shape.length)
            lines.append(geometry.points(
                geometry.simplify(shape.at(at), SIMPLIFY)))
            units.append(unit)
    return {"lines": lines, "unit": units}


def _termini(net, model, reach=TERMINUS):
    """The units within `reach` of either end of any shape.

    Asked of every shape the unit appears on, not just the one it is drawn from:
    a unit that is a terminus anywhere is a terminus in the numbers, since the
    layover there is folded into the same average.
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


def reading(model, units, now, floor=CONFIDENCE):
    """The ratio for each segment, or None where too little has been seen.

    The weight asked of is the slow layer's, decayed to `now`: it is the one the
    unit's own number is built from, so it answers "has anything driven here
    lately" rather than "does the model have an opinion", which it always does.
    """
    slot = model.slot(now)
    pace = model.pace.read(now, slot)
    _, weight = model.pace.cs.read(now)
    return {"t": int(now),
            "ratio": [round(float(pace[u]), 3) if weight[u] >= floor else None
                      for u in units]}


class Cache:
    """One reading per `PERIOD` seconds, serialised once.

    Reading it is a pass over every unit and a JSON array of tens of thousands
    of numbers, while the numbers themselves move on the scale of minutes. Every
    client polling inside the same period therefore gets the same bytes.
    """

    def __init__(self, model, units, period=PERIOD):
        self.model, self.units, self.period = model, units, period
        self.epoch, self.body = None, b""

    def read(self, now):
        epoch = int(now // self.period)
        if epoch != self.epoch:
            self.epoch = epoch
            self.body = json.dumps(reading(self.model, self.units, now)).encode()
        return self.body
