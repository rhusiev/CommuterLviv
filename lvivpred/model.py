"""Travel-time model.

A stretch of road costs a vehicle two separate things, and they behave nothing
alike, so the model learns them separately:

  pace  seconds per metre while rolling. Scales with distance. Travel time is
        linear in pace, which is why pace is stored rather than speed - paces
        can be averaged and added, speeds cannot.
  hold  seconds spent stationary per crossing. Does not scale with anything.
        A bus stop, a red light, a queue at a junction. Charged to the place.

Time to cross a cell is length x pace + hold. A single speed cannot express
standing still - as distance goes to zero the implied speed goes to zero and
any clip on it silently discards the wait - so the two terms stay apart until
an arrival time is actually wanted.

Both quantities are learned in three nested layers, each backing off to the
next when it has too little data:

  cell      one 100 m slice of one shape       - route-specific, sparsest
  corridor  a 120 m ground square + heading    - pooled across every route that
                                                 drives that street the same way
  global    one number for the whole network   - always available

Each layer keeps a fast and a slow exponentially weighted mean. The slow one is
the baseline for this stretch of road; the fast one is what traffic is doing
right now. The fast one wins wherever it has support.

Pace is not learned directly. What is learned is a multiplier on the pace the
timetable implies for that cell at that hour of the day. The timetable already
knows two things worth keeping: that the old town is slower than the ring road,
and that five in the afternoon is slower than five in the morning - the same
pattern takes up to 1.93x as long depending on when it runs. Learning the
ratio means the layers only have to explain what the timetable got wrong, which
is a far smaller and far more poolable quantity than the pace itself.

Hold has no such prior and is learned in seconds, starting at zero.
"""
import datetime
import zoneinfo

import numpy as np

PACE_CLIP = (0.020, 2.0)     # s/m: 180 km/h .. 1.8 km/h while actually rolling
HOLD_CLIP = (0.0, 240.0)     # s standing per crossing
RATIO_CLIP = (0.15, 8.0)     # observed pace over timetabled pace
PACE0 = 1 / 7.0              # s/m, fallback where the timetable says nothing
K_CELL = 4.0                 # observations before a cell outweighs its corridor
K_CORR = 4.0
SLOTS = 24                   # timetable prior resolution: one slot per hour
TZ = zoneinfo.ZoneInfo("Europe/Kyiv")


def group(keys, vals, weights):
    """Collapse repeated keys into one weighted mean each.

    Every update is batched, so the same cell is nearly always reported by
    several vehicles at once. Fancy-index assignment keeps only the last of a
    repeated index and silently discards the rest, so they are summed here
    first. Zero-weight entries are dropped rather than averaged, since a group
    made only of those has no mean at all.
    """
    keep = weights > 0
    keys, vals, weights = keys[keep], vals[keep], weights[keep]
    if not len(keys):
        return keys, vals, weights
    o = np.argsort(keys, kind="stable")
    k, v, w = keys[o], vals[o], weights[o]
    edge = np.concatenate([[0], np.nonzero(np.diff(k))[0] + 1])
    ws = np.add.reduceat(w, edge)
    return k[edge], np.add.reduceat(v * w, edge) / ws, ws


class Ewma:
    """Exponentially weighted mean with a decaying effective count."""

    def __init__(self, n, half_life, init):
        self.tau = half_life / np.log(2.0)
        self.mean = np.full(n, init, dtype=float)
        self.w = np.zeros(n)
        self.t = np.full(n, -np.inf)

    def _decay(self, t, now):
        """Weight left over from an observation made at t. Never seen (t = -inf)
        gives exactly zero; the cap only keeps exp from overflowing."""
        return np.exp(-np.minimum((now - t) / self.tau, 700.0))

    def update(self, idx, val, now, weight):
        idx, val, weight = group(idx, val, weight)
        w0 = self.w[idx] * self._decay(self.t[idx], now)
        w1 = w0 + weight
        self.mean[idx] = (self.mean[idx] * w0 + val * weight) / w1
        self.w[idx] = w1
        self.t[idx] = now

    def read(self, now):
        return self.mean, self.w * self._decay(self.t, now)


class Layer:
    """One quantity, learned at cell / corridor / global scale."""

    def __init__(self, ncell, ncorr, cell_corr, init, fast_hl, slow_hl):
        self.cell_corr = cell_corr
        self.cf = Ewma(ncell, fast_hl, init)
        self.cs = Ewma(ncell, slow_hl, init)
        self.rf = Ewma(ncorr, fast_hl, init)
        self.rs = Ewma(ncorr, slow_hl, init)
        self.g = Ewma(1, slow_hl, init)

    def update(self, cells, vals, now, weights, corr):
        total = weights.sum()
        if total <= 0.0:
            return
        self.cf.update(cells, vals, now, weights)
        self.cs.update(cells, vals, now, weights)
        cu, vu, wu = corr
        self.rf.update(cu, vu, now, wu)
        self.rs.update(cu, vu, now, wu)
        self.g.update(np.zeros(1, dtype=int),
                      np.array([np.average(vals, weights=weights)]),
                      now, np.array([total]))

    def read(self, now):
        gm, gw = self.g.read(now)
        rfm, rfw = self.rf.read(now)
        rsm, rsw = self.rs.read(now)
        corr = (rfm * rfw + rsm * rsw + gm[0] * K_CORR) / (rfw + rsw + K_CORR)
        cfm, cfw = self.cf.read(now)
        csm, csw = self.cs.read(now)
        base = corr[self.cell_corr]
        return (cfm * cfw + csm * csw + base * K_CELL) / (cfw + csw + K_CELL)


class PaceModel:
    def __init__(self, net, fast_hl=480.0, slow_hl=5400.0):
        self.net = net
        self.shape_base = {}
        base = 0
        corr = []
        for sid in sorted(net.shapes):
            s = net.shapes[sid]
            self.shape_base[sid] = base
            base += s.cells
            corr.append(s.corridor)
        self.ncell = base
        _, inv = np.unique(np.concatenate(corr), return_inverse=True)
        self.cell_corr = inv.astype(np.int64)
        self.ncorr = int(inv.max()) + 1

        self.cell_len = np.zeros(self.ncell)
        for sid, b in self.shape_base.items():
            s = net.shapes[sid]
            self.cell_len[b:b + s.cells] = s.length / s.cells

        args = (self.ncell, self.ncorr, self.cell_corr)
        self.pace = Layer(*args, 1.0, fast_hl, slow_hl)
        self.hold = Layer(*args, 0.0, fast_hl, slow_hl)
        self.prior = self._schedule_prior()

        self._cum = np.zeros(self.ncell + 1)
        self._prior_t = None
        self._per_cell = self.prior[0] * self.cell_len

    def _schedule_prior(self):
        """Timetabled pace for every cell, at every hour of the day.

        Before a vehicle has been watched anywhere, one number for the whole
        city is a poor guess: a cell on a ring road and a cell in the old town
        are nothing alike, and neither is the same street at eight in the
        morning and at eleven at night. The timetable distinguishes both, so
        its own stop-to-stop times shape the map and observations correct it.

        The prior is an effective pace - it contains the scheduled dwell as
        well as the driving - so hold starts at zero and the two separate as
        evidence arrives. Trips whose every scheduled gap is the same round
        number are a placeholder rather than a timing, and are left out. A cell
        with no timings at a given hour falls back to its own all-day mean, and
        a cell with no timings at all to one city-wide constant.
        """
        num = np.zeros((SLOTS, self.ncell))
        den = np.zeros((SLOTS, self.ncell))
        by_pattern = {}
        for trip, key in self.net.pattern_of.items():
            by_pattern.setdefault(key, []).append(trip)

        for (sid, _), trips in by_pattern.items():
            base = self.shape_base.get(sid)
            if base is None:
                continue
            dist = self.net.trip_stops[trips[0]][1]
            dd = np.diff(dist)
            if len(dd) < 2:
                continue
            by_slot = {}
            for t in trips:
                sched = self.net.trip_stops[t][2]
                dt = np.diff(sched)
                if np.ptp(dt) > 1.0:
                    by_slot.setdefault(int(sched[0] // 3600) % SLOTS, []).append(dt)
            if not by_slot:
                continue
            last = self.net.shapes[sid].cells - 1
            edge = base + np.minimum((dist / self.cell_len[base]).astype(int), last)
            for slot, rows in by_slot.items():
                dt = np.mean(rows, axis=0)
                ok = (dd > 20.0) & (dt > 5.0)
                for a, b, p in zip(edge[:-1][ok], edge[1:][ok], dt[ok] / dd[ok]):
                    num[slot, a:b + 1] += p
                    den[slot, a:b + 1] += 1.0

        tot = den.sum(axis=0)
        cell = np.where(tot > 0, num.sum(axis=0) / np.maximum(tot, 1e-9), PACE0)
        out = np.where(den > 0, num / np.maximum(den, 1e-9), cell)
        return np.clip(out, *PACE_CLIP)

    def prior_at(self, now):
        """The timetabled pace of every cell at this instant.

        Hours are interpolated rather than stepped: a prediction made at 08:55
        for an arrival at 09:10 would otherwise be built entirely out of the
        eight o'clock timetable and jump when the clock ticked over.
        """
        if now != self._prior_t:
            local = datetime.datetime.fromtimestamp(now, TZ)
            k = local.hour + local.minute / 60.0
            i, f = int(k), k - int(k)
            self._prior_row = ((1.0 - f) * self.prior[i]
                               + f * self.prior[(i + 1) % SLOTS])
            self._prior_t = now
        return self._prior_row

    def observe(self, cells, dist, pace, hold, hold_w, now):
        """Record cell crossings, finished or still in progress.

        A crossing weighs its share of the cell for pace, and one whole
        observation for hold - a cell crossed without stopping is real evidence
        that nothing waits there, and has to count as such. A crossing reported
        while still in progress carries only the fraction of that weight it has
        earned so far; the rest arrives when it finishes.
        """
        cells = np.asarray(cells)
        w_pace = dist / self.cell_len[cells]
        ratio = np.clip(pace / self.prior_at(now)[cells], *RATIO_CLIP)
        held = np.clip(hold, *HOLD_CLIP)
        corr = self.cell_corr[cells]
        self.pace.update(cells, ratio, now, w_pace, group(corr, ratio, w_pace))
        self.hold.update(cells, held, now, hold_w, group(corr, held, hold_w))

    def expected(self, cells):
        """Seconds a crossing of these cells is currently believed to take."""
        return self._per_cell[cells]

    def refresh(self, now):
        """Cumulative travel time along every shape, so an ETA is a subtraction."""
        self._pace = self.pace.read(now) * self.prior_at(now)
        self._hold = self.hold.read(now)
        self._per_cell = self._pace * self.cell_len + self._hold
        np.cumsum(self._per_cell, out=self._cum[1:])

    def time_between(self, shape_id, d0, d1):
        """Seconds to go from d0 to d1 metres along a shape (vectorised in d1)."""
        s = self.net.shapes[shape_id]
        b = self.shape_base[shape_id]
        cl = s.length / s.cells

        def upto(d):
            d = np.clip(np.asarray(d, dtype=float), 0.0, s.length)
            i = np.minimum((d / cl).astype(int), s.cells - 1)
            return (self._cum[b + i] - self._cum[b]
                    + (d / cl - i) * self._per_cell[b + i])

        return np.maximum(upto(d1) - upto(d0), 0.0)
