"""The live city: the same tracker and the same model, stepped on wall time.

The offline replay in `replay.py` reads recorded fixes and advances a 60 s epoch
whenever a fix crosses one. This does exactly that, with two differences: the
fixes come from the network instead of from SQLite, and the epoch is advanced by
the clock instead of by the data. Every line that decides a number - folding a
fix into a track, handing crossings to the model, asking for arrival times - is
called out of `replay` and `track`, so the numbers this service publishes are
the numbers the offline comparison measured. Nothing about the model is
reimplemented here.

Two things are published, at two rates, because they change at two rates:

  positions  every poll (~5 s), straight off the tracks, no model consulted
  arrivals   every epoch (60 s), which is when the model updates at all

Everything published is frozen and replaced wholesale. Readers - websocket
clients, HTTP handlers - only ever hold a reference to one of these objects, so
they never see the engine's state half-updated and never need a lock.
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
    """The parts of the network that do not change while the service runs.

    Built once, sent to a client once, and referred to by index everywhere
    after that: a route is two bytes on the wire and a stop is two bytes,
    rather than the 30-odd characters of their feed ids.
    """

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
        """The catalog as the web app receives it. Static for the process's
        life, so the client caches it against the build stamp."""
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
        """Only the vehicles on these route indexes. `keep` is a boolean mask
        over the catalog's routes, so the filter is one vectorised take and
        costs the same whether a client watches one route or all of them."""
        return self.veh[keep[self.veh["route"]]] if len(self.veh) else self.veh


@dataclass(frozen=True, slots=True)
class Arrivals:
    t: float
    eta: np.ndarray = field(default_factory=lambda: np.zeros(0, ETA))
    start: np.ndarray = field(default_factory=lambda: np.zeros(1, np.int64))

    def at(self, stop_i):
        """Every arrival predicted for one stop, soonest first. `eta` is kept
        sorted by stop and `start` holds each stop's first row, so this is a
        slice rather than a scan of four thousand predictions."""
        if stop_i + 1 >= len(self.start):
            return self.eta[:0]
        return self.eta[self.start[stop_i]:self.start[stop_i + 1]]


class Live:
    """Vehicle tracks, the pace model, and the two published snapshots.

    Single-threaded by construction: `fix`, `poll_done` and `epoch` are called
    from one place, in order. The service runs them in a worker thread and
    keeps them off the event loop, because one epoch is around 200 ms of numpy
    and a frame budget is 16.
    """

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
        """One vehicle position report, folded in exactly as the replay folds
        a recorded one. Returns False if it was of no use."""
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
        """Republish where every vehicle is. No model, no allocation beyond the
        one array: this runs eight times more often than the model does."""
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
        """One model step: the same four calls `replay._flush` makes, in the
        same order, then the arrivals they imply."""
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
            # Ids are reused once a vehicle is pruned, so the counter only ever
            # reaches the largest number of vehicles seen at once - around 600 -
            # rather than walking off the end of a 16-bit field after a month.
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
        """Whether the map may show this vehicle as under way.

        The tracker carries the variance of its own speed estimate in `tr.P`,
        so the question asked is whether the speed clears the stationary
        threshold by more than its own error, rather than whether a noisy
        number happens to be above a constant. A vehicle we are unsure about
        is drawn standing, which is the answer that can only be dull rather
        than wrong.
        """
        sd = math.sqrt(max(float(tr.P[1, 1]), 0.0))
        return tr.v - SURE * sd > track.HOLD_SPEED

    def _believed(self, tr, now, moving):
        """Where the map puts the vehicle. Its last known place until there is
        evidence of motion, and then only `DAMP` of the distance the dead
        reckoning claims: drawn short of where it is, a vehicle reads as
        caution; drawn past a stop it has not reached, it reads as a lie.

        `replay.believed` itself is untouched and the arrival times still come
        from it, so the numbers the offline comparison measured are the numbers
        the timetable shows. This holds back the marker, nothing else.
        """
        if not moving:
            return min(tr.s, tr.shape.length)
        return tr.s + (replay.believed(tr, now) - tr.s) * DAMP

    def _heading(self, tr, s):
        """Which way the vehicle is going: the direction of its own route at
        the point it has reached, averaged over `HEAD_SPAN` either side so a
        single bent segment does not swing the arrow.

        The feed reports a bearing as well, and it is deliberately not used. It
        arrives stale, it is meaningless while a vehicle stands, and it
        disagreed with the route often enough to point arrows sideways and
        sometimes backwards. The route geometry cannot: `s` grows in the
        direction of travel by construction, and it is the same geometry the
        arrival times are computed along, so the arrow and the times agree.
        """
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
