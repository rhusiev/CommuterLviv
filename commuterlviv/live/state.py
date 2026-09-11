"""The live city: the same tracker and the same model, stepped on wall time.

Every number comes from `replay` and `track`, so what this publishes is what the
offline comparison measured; nothing about the model is reimplemented here.

Two things are published, at two rates: positions every poll (~5 s), straight off
the tracks with no model consulted, and arrivals every epoch, which is when the
model updates. Both are frozen and replaced wholesale, so readers never see
half-updated state and need no lock.
"""
import math
import time
from dataclasses import dataclass, field

import numpy as np

from .. import network, replay, track

VEH = np.dtype([("id", "u2"), ("route", "u2"), ("lat", "f8"), ("lon", "f8"),
                ("heading", "u2"), ("flags", "u1"), ("run", "u2")])
ETA = np.dtype([("stop", "u2"), ("route", "u2"), ("veh", "u2"), ("t", "i4")])

FRESH = 30.0             # s since the last fix within which a marker is solid
MAX_WIRE = 65535         # vehicle ids are 16-bit on the wire
HEAD_SPAN = 25.0         # m either side of the vehicle the arrow averages over
SURE = 1.0               # sigmas the speed must clear "stopped" by to be motion
DAMP = 0.7               # of the dead reckoned distance the map draws

STALE, MOVING = 1, 2     # the flag bits, mirrored in `web/src/lib/wire.ts`


class Catalog:
    """The parts of the network that do not change while the service runs;
    sent to a client once, then referred to by index so routes and stops are
    two bytes each on the wire rather than their feed ids."""

    def __init__(self, net):
        self.routes = sorted(net.routes, key=lambda r: (
            net.routes[r]["type"], _numkey(net.routes[r]["short"])))
        self.route_i = {r: i for i, r in enumerate(self.routes)}
        serving = {}
        for trip, (stops, _, _) in net.trip_stops.items():
            r = net.trip_route.get(trip)
            if r is None:
                continue
            for s in stops:
                serving.setdefault(s, set()).add(r)
        self.stops = sorted(serving)
        self.stop_i = {s: i for i, s in enumerate(self.stops)}
        self.stop_routes = [sorted(self.route_i[r] for r in serving[s]
                                   if r in self.route_i) for s in self.stops]
        self.lat = np.array([net.stops[s]["lat"] for s in self.stops])
        self.lon = np.array([net.stops[s]["lon"] for s in self.stops])
        self.net = net

    def describe(self):
        """The catalog as the web app receives it; static for the process."""
        net = self.net
        return {
            "routes": [{"id": r, "short": net.routes[r]["short"],
                        "long": net.routes[r]["long"],
                        "type": net.routes[r]["type"]} for r in self.routes],
            "stops": [{"id": s, "name": net.stops[s]["name"],
                       "code": net.stops[s]["code"],
                       "lat": round(net.stops[s]["lat"], 6),
                       "lon": round(net.stops[s]["lon"], 6),
                       "routes": rs}
                      for s, rs in zip(self.stops, self.stop_routes)],
        }


def _numkey(short):
    """Sort 3, 3A, 10 the way a rider reads them, not the way ASCII does."""
    digits = "".join(c for c in short if c.isdigit())
    return (int(digits) if digits else 0, short)


@dataclass(frozen=True, slots=True)
class Positions:
    t: float
    veh: np.ndarray = field(default_factory=lambda: np.zeros(0, VEH))

    def by_route(self, keep):
        """Only the vehicles on these route indexes; `keep` is a boolean mask
        over the catalog's routes."""
        return self.veh[keep[self.veh["route"]]] if len(self.veh) else self.veh


@dataclass(frozen=True, slots=True)
class Arrivals:
    t: float
    eta: np.ndarray = field(default_factory=lambda: np.zeros(0, ETA))
    start: np.ndarray = field(default_factory=lambda: np.zeros(1, np.int64))

    def at(self, stop_i):
        """Every arrival predicted for one stop, soonest first; `eta` is sorted
        by stop and `start` holds each stop's first row, so this is a slice."""
        if stop_i + 1 >= len(self.start):
            return self.eta[:0]
        return self.eta[self.start[stop_i]:self.start[stop_i + 1]]

    def of(self, veh_i):
        """One vehicle's road ahead, soonest first; a scan, since `eta` is
        indexed by stop and not by vehicle."""
        rows = self.eta[self.eta["veh"] == veh_i]
        return rows[np.argsort(rows["t"], kind="stable")]


class Live:
    """Vehicle tracks, the pace model, and the two published snapshots.
    Single-threaded by construction: `fix`, `poll_done` and `epoch` must be
    called from one place, in order."""

    def __init__(self, net, cfg, catalog=None, epoch=replay.EPOCH):
        self.net = net
        self.cat = catalog or Catalog(net)
        self.model = replay.build(net, cfg)
        self.epoch_s = epoch
        self.tracks, self.runs, self.closed = {}, {}, []
        self.offset = {} if cfg.vehicle_offset != "off" else None
        self.wire, self.free, self.next_wire = {}, [], 0
        self.next_epoch = None
        self.epochs = 0
        self.positions = Positions(0.0)
        self.arrivals = Arrivals(0.0)
        self.started = time.time()

    @property
    def variant(self):
        return self.model.cfg.name

    def fix(self, veh, ts, lat, lon, speed, odometer, trip):
        """One vehicle position report, folded in as the replay folds a recorded
        one. Returns False if it was of no use."""
        if trip not in self.net.trip_stops:
            return False
        tr = self.tracks.get(veh)
        if tr is None:
            tr = self.tracks[veh] = track.Track(veh, self.runs.get(veh, 0))
        done, _ = track.observe(tr, self.net, float(ts), lat, lon,
                                speed, odometer, trip)
        if done:
            base = self.model.shape_base[tr.shape_id]
            self.closed.extend((base + c.i, c, veh) for c in done)
        return True

    def poll_done(self, now=None):
        """Republish where every vehicle is; the model is not consulted."""
        now = now or time.time()
        rows = np.zeros(len(self.tracks), VEH)
        n = 0
        for veh, tr in self.tracks.items():
            if not replay.predictable(tr, now):
                continue
            route = self.net.trip_route.get(tr.trip)
            ri = self.cat.route_i.get(route)
            if ri is None:
                continue
            moving = self._moving(tr)
            s = self._believed(tr, now, moving)
            rows[n] = (self._wire(veh), ri, *self._latlon(tr, s),
                       self._heading(tr, s), self._flags(tr, now, moving),
                       tr.run % 65536)
            n += 1
        self.positions = Positions(now, rows[:n])
        return self.positions

    def epoch(self, now=None):
        """One model step: the same calls `replay._flush` makes, in the same
        order, then the arrivals they imply."""
        now = now or time.time()
        self.model.emitting = True
        replay.drain(self.model, self.tracks, self.closed, now, self.offset)
        replay.prune(self.tracks, self.runs, now)
        for veh in [v for v in self.wire if v not in self.tracks]:
            self.free.append(self.wire.pop(veh))
        self.model.refresh(now)
        self.epochs += 1
        self.arrivals = self._arrivals(now)
        return self.arrivals

    def _arrivals(self, now):
        rows = []
        for veh, tr in self.tracks.items():
            got = replay.etas(self.model, tr, veh, now, self.offset)
            if got is None:
                continue
            i, _, dt, k = got
            ri = self.cat.route_i.get(self.net.trip_route.get(tr.trip))
            if ri is None:
                continue
            w = self._wire(veh)
            stops = tr.stops
            for j, at in zip(i + k, np.rint(now + dt[k]).astype("i8")):
                si = self.cat.stop_i.get(stops[j])
                if si is not None:
                    rows.append((si, ri, w, at))
        eta = np.array(rows, dtype=ETA) if rows else np.zeros(0, ETA)
        eta = eta[np.lexsort((eta["t"], eta["stop"]))]
        start = np.searchsorted(eta["stop"], np.arange(len(self.cat.stops) + 1))
        return Arrivals(now, eta, start.astype(np.int64))

    def _wire(self, veh):
        w = self.wire.get(veh)
        if w is None:
            # ids are reused once a vehicle is pruned, so the counter stays
            # inside the 16-bit wire field over a long run
            if self.free:
                w = self.free.pop()
            else:
                w, self.next_wire = self.next_wire, self.next_wire + 1
                if w > MAX_WIRE:
                    raise RuntimeError("more than 65536 vehicles tracked at once")
            self.wire[veh] = w
        return w

    def _latlon(self, tr, s):
        x, y = tr.shape.at(s)
        return y / network.KY + network.LAT0, x / network.KX + network.LON0

    def _moving(self, tr):
        """Whether the map may show this vehicle as under way: the speed must
        clear the stationary threshold by `SURE` of its own standard error."""
        sd = math.sqrt(max(float(tr.P[1, 1]), 0.0))
        return tr.v - SURE * sd > track.HOLD_SPEED

    def _believed(self, tr, now, moving):
        """Where the map puts the vehicle: its last known place until there is
        evidence of motion, then only `DAMP` of the dead reckoned distance.
        Affects the marker only; arrival times still use `replay.believed`."""
        if not moving:
            return min(tr.s, tr.shape.length)
        return tr.s + (replay.believed(tr, now) - tr.s) * DAMP

    def _heading(self, tr, s):
        """Which way the vehicle is going, from the route geometry at the point
        it has reached, averaged over `HEAD_SPAN` either side. The feed's own
        bearing is not used: it arrives stale and often disagrees with the
        route."""
        span = min(HEAD_SPAN, tr.shape.length / 2)
        a = tr.shape.at(max(s - span, 0.0))
        c = tr.shape.at(min(s + span, tr.shape.length))
        dx, dy = c[0] - a[0], c[1] - a[1]
        if dx == 0.0 and dy == 0.0:
            return 0
        return int(round(math.degrees(math.atan2(dx, dy)))) % 360

    def _flags(self, tr, now, moving):
        return (STALE if now - tr.ts > FRESH else 0) | (MOVING if moving else 0)

    def health(self):
        return {"variant": self.variant, "epochs": self.epochs,
                "tracks": len(self.tracks),
                "vehicles": int(len(self.positions.veh)),
                "arrivals": int(len(self.arrivals.eta)),
                "positions_age": round(time.time() - self.positions.t, 1),
                "arrivals_age": round(time.time() - self.arrivals.t, 1),
                "uptime": round(time.time() - self.started, 1)}
