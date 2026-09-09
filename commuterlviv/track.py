"""Per-vehicle state: where it is along its trip, and how fast.

The feed gives an irregular fix every ~10 s. Three things have to come out of
that stream: a smoothed position to predict from, travel-time observations to
feed the pace model, and the actual moment each stop was passed (ground truth).

Position is tracked as one number - distance along the trip's shape - by a
two-state Kalman filter on (distance, speed). The increment between fixes comes
from the vehicle's own odometer rather than from differencing two map-matched
positions: the odometer is an integrated path length good to about 2 m, while
map-matching error is correlated between neighbouring fixes and would bias the
increment. GPS is still used, but only to correct absolute position.

Time is reported split in two, because the road spends it in two different ways.
Time while rolling scales with distance. Time while stationary - a bus stop, a
red light, a queue at a junction - does not scale with anything; it belongs to
the place it happened. A single speed cannot express standing still, so the two
are counted separately and only recombined when an arrival time is wanted.
"""
import numpy as np

from .network import project, to_xy, candidates

GAP_RESET = 300.0        # s without a fix: state is stale, start over
JUMP_BACK = 150.0        # m backwards: a loop restart, not noise
MAX_LATERAL = 60.0       # m off the shape: refuse to trust the snap
HOLD_SPEED = 0.7         # m/s below which the vehicle counts as stationary
HOLD_DIST = 3.0          # m of progress below which it counts as stationary
MAX_HOLD = 240.0         # s standing: a layover or a breakdown, not traffic
SIG_SNAP = 12.0          # m, along-track map-match error
SIG_SPEED = 1.5          # m/s, reported speed error
SIG_ACC = 0.8            # m/s^2, unmodelled acceleration


class Cell:
    """One crossing of one cell, and how much of it has been reported.

    A crossing is reported as it happens rather than only once it ends. Waiting
    for the end would report every fast crossing sooner than every slow one, so
    the model would hear about a jam only after the jam had cleared - exactly
    the wrong time. Reporting in progress removes that lag entirely.

    Pace and hold are always the crossing's totals so far; only the weights are
    incremental, so one crossing contributes its own weight and no more.
    """
    __slots__ = ("i", "whole", "dist", "move", "hold", "sent_d", "sent_w")

    def __init__(self, i, whole):
        self.i = i
        self.whole = whole
        self.dist = self.move = self.hold = 0.0
        self.sent_d = self.sent_w = 0.0

    def take(self, expected, final=False):
        """The part not yet reported: (metres, pace, hold, hold weight), or None.

        A cell we joined half way through teaches nothing - its totals are
        missing whatever happened before we arrived - so it is never reported.
        """
        if not self.whole or self.dist <= 0.0:
            return None
        share = 1.0 if final else min((self.move + self.hold) / max(expected, 1.0), 1.0)
        d, w = self.dist - self.sent_d, max(share - self.sent_w, 0.0)
        if d <= 0.0 and w <= 0.0:
            return None
        self.sent_d, self.sent_w = self.dist, self.sent_w + w
        return d, self.move / self.dist, min(self.hold, MAX_HOLD), w


class Track:
    __slots__ = ("veh", "trip", "shape_id", "shape", "stops", "sdist", "sched", "clen",
                 "s", "v", "P", "ts", "odo", "next_stop", "run", "cell")

    def __init__(self, veh, run=0):
        self.veh = veh
        self.trip = None
        self.ts = None
        self.run = run

    def reset(self, trip, net, ts):
        self.trip = trip
        self.run += 1
        self.shape_id = net.trip_shape[trip]
        self.shape = net.shapes[self.shape_id]
        self.stops, self.sdist, self.sched = net.trip_stops[trip]
        self.clen = self.shape.length / self.shape.cells
        self.s = None
        self.v = 0.0
        self.P = np.array([[400.0, 0.0], [0.0, 25.0]])
        self.ts = ts
        self.odo = None
        self.next_stop = 0
        self.cell = None

    def snap(self, xy, gap):
        """Map-match, searching near where the vehicle should be by now."""
        if self.s is None:
            d, e = candidates(self.shape, xy)
            return float(d[0]), float(e[0])
        reach = 200.0 + 25.0 * min(gap, 120.0)
        return project(self.shape.xy, self.shape.cum, xy,
                       self.s - 0.5 * reach, self.s + reach)


def observe(tr, net, ts, lat, lon, speed, odometer, trip):
    """Fold one fix into the track. Returns (done, passings).

    done     every Cell the vehicle finished crossing since the last fix
    passings (stop_index, crossing_time, fix_gap) for stops passed since the
             last fix; the gap is how wide the interval the time was
             interpolated across was, which bounds how exact it can be
    """
    if trip != tr.trip or tr.ts is None or ts - tr.ts > GAP_RESET:
        tr.reset(trip, net, ts)
    gap = max(ts - tr.ts, 0.0)
    xy = to_xy(np.array([lat]), np.array([lon]))[0]

    z_s, lat_err = tr.snap(xy, gap)
    odo_m = odometer * 1000.0
    u = None if (tr.odo is None or odo_m < tr.odo) else odo_m - tr.odo
    tr.odo = odo_m

    if tr.s is None or (lat_err > MAX_LATERAL and u is None):
        tr.s, tr.v, tr.ts = z_s, speed, ts
        tr.next_stop = int(np.searchsorted(tr.sdist, tr.s, "right"))
        tr.cell = None
        return [], []

    s0 = tr.s
    if u is not None and gap > 0:
        s_pred, v_pred = tr.s + u, u / gap
        var_u = (1.0 + 0.02 * u) ** 2
    else:
        s_pred, v_pred = tr.s + tr.v * gap, tr.v
        var_u = (0.5 * SIG_ACC * gap * gap) ** 2
    F = np.array([[1.0, gap], [0.0, 1.0]])
    P = F @ tr.P @ F.T
    P[0, 0] += var_u
    P[1, 1] += (SIG_ACC * gap) ** 2

    x0 = np.array([s_pred, v_pred])
    R = np.diag([SIG_SNAP ** 2 if lat_err <= MAX_LATERAL else 1e6, SIG_SPEED ** 2])
    K = P @ np.linalg.inv(P + R)
    x = x0 + K @ (np.array([z_s, speed]) - x0)
    tr.P = (np.eye(2) - K) @ P
    tr.s = float(np.clip(x[0], 0.0, tr.shape.length))
    tr.v = float(max(x[1], 0.0))
    tr.ts = ts

    if tr.s < s0 - JUMP_BACK:
        tr.next_stop = int(np.searchsorted(tr.sdist, tr.s, "right"))
        tr.run += 1
        tr.cell = None
        return [], []

    dist = tr.s - s0
    holding = dist < HOLD_DIST and speed < HOLD_SPEED
    done = _spread(tr, s0, dist, gap, holding)

    passings = []
    i = tr.next_stop
    while i < len(tr.sdist) and tr.sdist[i] <= tr.s:
        f = (tr.sdist[i] - s0) / dist if dist > 0 else 0.0
        passings.append((i, ts - gap + f * gap, gap))
        i += 1
    tr.next_stop = i
    return done, passings


def _spread(tr, s0, dist, gap, holding):
    """Charge this interval's time to the cells it happened in.

    Standing time is charged whole to the cell the vehicle was standing in.
    Rolling time is split between cells in proportion to distance covered.
    """
    cl = tr.clen
    last = tr.shape.cells - 1
    i0 = min(int(s0 / cl), last)
    if tr.cell is None:
        tr.cell = Cell(i0, s0 <= i0 * cl + 1e-6)
    elif tr.cell.i != i0:
        tr.cell = Cell(i0, False)

    if holding or dist <= 0.0:
        tr.cell.hold += gap
        return []

    done = []
    i1 = min(int(tr.s / cl), last)
    for i in range(i0, i1 + 1):
        lo = s0 if s0 > i * cl else i * cl
        hi = tr.s if tr.s < (i + 1) * cl else (i + 1) * cl
        if hi <= lo:
            continue
        if i != tr.cell.i:
            done.append(tr.cell)
            tr.cell = Cell(i, True)
        tr.cell.dist += hi - lo
        tr.cell.move += gap * (hi - lo) / dist
    return done
