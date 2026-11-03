"""The live city: the same tracker and the same model, stepped on wall time.

Every number comes from `replay` and `track`, so what this publishes is what the
offline comparison measured; nothing about the model is reimplemented here.

Two things are published, at two rates: positions every poll (~5 s), straight off
the tracks with no model consulted, and arrivals every epoch, which is when the
model updates. Both are frozen and replaced wholesale, so readers never see
half-updated state and need no lock.
"""
import collections
import functools
import hashlib
import json
import math
import time
from dataclasses import dataclass, field

import numpy as np

from .. import layover, localtime, network, replay, track

VEH = np.dtype([("id", "u2"), ("route", "u2"), ("lat", "f8"), ("lon", "f8"),
                ("heading", "u2"), ("flags", "u1")])
# `planned`: the vehicle has yet to start this trip, so the time is anchored on
# the timetable's departure from its first stop rather than on where it is
ETA = np.dtype([("stop", "u2"), ("route", "u2"), ("veh", "u2"), ("t", "i4"),
                ("planned", "u1")])

FRESH = 30.0             # s since the last fix within which a marker is solid
MAX_WIRE = 65535         # vehicle ids are 16-bit on the wire
HEAD_SPAN = 25.0         # m either side of the vehicle the arrow averages over
SURE = 1.0               # sigmas the speed must clear "stopped" by to be motion
DAMP = 0.7               # of the dead reckoned distance the map draws

# The flag bits, mirrored in `web/src/lib/wire.ts` and `mobile/lib/src/wire.dart`.
# LOW_FLOOR is the feed's own word for the vehicle, said only where it says so:
# it marks next to no bus, so its absence means unknown, not high floor
STALE, MOVING, LOW_FLOOR, STUCK = 1, 2, 4, 8
STUCK_S = 300.0          # s standing still mid-route before an arrival is doubted
ENDS_M = 150.0           # m from either end of its line a vehicle stands at will


def etag(body):
    """A weak ETag that changes whenever the body does."""
    return f'W/"{hashlib.blake2b(body, digest_size=8).hexdigest()}"'


class Catalog:
    """The parts of the network that do not change while it is served; sent
    to a client once, then referred to by index so routes and stops are two
    bytes each on the wire rather than their feed ids. A new feed is a new
    catalog, and `tag` tells a client holding the old one."""

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
        self.net = net

    @functools.cached_property
    def body(self):
        return json.dumps(self.describe()).encode()

    @functools.cached_property
    def tag(self):
        return etag(self.body)

    def describe(self):
        """The catalog as the clients receive it."""
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
        self.wire, self.free, self.next_wire = {}, collections.deque(), 0
        # by feed id: (low floor, fleet number or plate); since when it stood
        self.meta, self.still = {}, {}
        self.next_epoch = None
        self.epochs = 0
        self.reporting = 0       # vehicles `replay.fresh` at the last epoch
        self.positions = Positions(0.0)
        self.arrivals = Arrivals(0.0)
        self.started = time.time()

    @property
    def variant(self):
        return self.model.cfg.name

    def fix(self, veh, ts, lat, lon, speed, odometer, trip, label=None,
            plate=None):
        """One vehicle position report, folded in as the replay folds a recorded
        one. Returns False if it was of no use. `label` and `plate` are the
        feed's word on the vehicle itself, kept for the map and its card."""
        if label is not None or plate is not None:
            self.meta[veh] = (label == "low_floor", (plate or "").strip())
        if trip not in self.net.trip_stops:
            return False
        tr = self.tracks.get(veh)
        if tr is None:
            tr = self.tracks[veh] = track.Track(veh, self.runs.get(veh, 0))
        done, passings = track.observe(tr, self.net, float(ts), lat, lon,
                                       speed, odometer, trip)
        self.model.layovers.follow(veh, tr)
        for i, t, gap in passings:
            self.model.boost.passed(veh, tr, i, t, gap)
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
            ri = self._route_i(tr)
            if ri is None:
                continue
            moving = self._moving(tr)
            if moving:
                self.still.pop(veh, None)
            else:
                self.still.setdefault(veh, now)
            s = self._believed(tr, now, moving)
            rows[n] = (self._wire(veh), ri, *self._latlon(tr, s),
                       self._heading(tr, s), self._flags(veh, tr, now, s))
            n += 1
        self.positions = Positions(now, rows[:n])
        return self.positions

    def epoch(self, now=None):
        """One model step - `replay.step`, the same call the offline replay
        makes - then the arrivals it implies."""
        now = now or time.time()
        fc = replay.step(self.model, self.tracks, self.runs, self.closed, now)
        for veh in [v for v in self.wire if v not in self.tracks]:
            self.free.append(self.wire.pop(veh))
            self.meta.pop(veh, None)
            self.still.pop(veh, None)
        self.epochs += 1
        self.reporting = sum(replay.fresh(tr, now) for tr in self.tracks.values())
        self.arrivals = self._arrivals(fc, now)
        return self.arrivals

    def _arrivals(self, fc, now):
        """The epoch's forecast as the clients' rows: only here does a track
        need a route the catalog knows."""
        rows = []
        for (veh, tr), got in zip(fc.asked, fc.got):
            ri = self._route_i(tr)
            if got is None or ri is None:
                continue
            w = self._wire(veh)
            i, _, dt, k = got
            self._rows(rows, tr.stops, i + k, now + dt[k], ri, w, 0)
            self._next_trips(rows, tr.trip, now + float(dt[-1]), now, ri, w,
                             fc.running)
        for veh, tr, came in fc.standing:
            ri = self._route_i(tr)
            if ri is not None:
                self._next_trips(rows, tr.trip, came, now, ri, self._wire(veh),
                                 fc.running)
        eta = np.array(rows, dtype=ETA) if rows else np.zeros(0, ETA)
        eta = eta[np.lexsort((eta["t"], eta["stop"]))]
        start = np.searchsorted(eta["stop"], np.arange(len(self.cat.stops) + 1))
        return Arrivals(now, eta, start.astype(np.int64))

    def _route_i(self, tr):
        """The catalog's index of the route this track's trip is on, or None."""
        return self.cat.route_i.get(self.net.trip_route.get(tr.trip))

    def _rows(self, rows, stops, idx, at, ri, w, planned):
        for j, t in zip(idx, np.rint(at).astype("i8")):
            si = self.cat.stop_i.get(stops[j])
            if si is not None:
                rows.append((si, ri, w, t, planned))

    def _next_trips(self, rows, trip, ends, now, ri, w, running):
        """The trips this vehicle runs after the one it is on, within the
        horizon.

        The feed keeps a vehicle on its finished trip for as long as it stands
        at the terminus, and names the next one only as it pulls up to the first
        stop - so without this, the first stops of a line show nothing until the
        vehicle is already there. Each next trip leaves when its route's
        turnarounds say (`layover`), counted from when the vehicle got in, and
        the model times it from there. A trip another vehicle is already on is
        left to it.
        """
        horizon = now + replay.HORIZON
        while (trip := self.net.trip_next.get(trip)) is not None:
            if trip in running:
                return
            stops, dist, sched = self.net.trip_stops[trip]
            leave = self.model.layovers.leave(
                trip, layover.clock(sched[0], now, localtime.TZ), ends, now)
            if leave > horizon:
                return
            sid = self.net.trip_shape[trip]
            at = leave + self.model.time_between(sid, dist[0], dist)
            keep = np.flatnonzero(at <= horizon)
            self._rows(rows, stops, keep, at[keep], ri, w, 1)
            ends = float(at[-1])

    def _wire(self, veh):
        w = self.wire.get(veh)
        if w is None:
            # ids are reused once a vehicle is pruned, so the counter stays
            # inside the 16-bit wire field over a long run. Oldest first: a
            # client still holding a pruned vehicle's id - a planned or a
            # followed ride - is then least likely to find another under it
            if self.free:
                w = self.free.popleft()
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

    def _flags(self, veh, tr, now, s):
        moving = veh not in self.still
        low = self.meta.get(veh, (False, ""))[0]
        # A vehicle standing at either end of its line is laying over
        stuck = (not moving and now - self.still[veh] > STUCK_S
                 and ENDS_M < s < tr.shape.length - ENDS_M)
        return ((STALE if now - tr.ts > FRESH else 0) | (MOVING if moving else 0)
                | (LOW_FLOOR if low else 0) | (STUCK if stuck else 0))

    def vehicle(self, wire_id):
        """What the feed says of the vehicle sent as `wire_id`: its fleet number
        or plate, whether it is low floor, and when it last reported; None for
        an id no longer sent."""
        veh = next((v for v, w in self.wire.items() if w == wire_id), None)
        tr = self.tracks.get(veh)
        if tr is None:
            return None
        low, fleet = self.meta.get(veh, (False, ""))
        return {"fleet": fleet or None, "low_floor": low, "seen": round(tr.ts)}

    def health(self):
        return {"variant": self.variant, "epochs": self.epochs,
                "tracks": len(self.tracks),
                "vehicles": int(len(self.positions.veh)),
                "arrivals": int(len(self.arrivals.eta)),
                "reporting": self.reporting,
                "positions_age": round(time.time() - self.positions.t, 1),
                "arrivals_age": round(time.time() - self.arrivals.t, 1),
                "uptime": round(time.time() - self.started, 1)}
