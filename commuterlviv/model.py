"""Travel-time model.

A stretch of road costs two things that behave differently, so they are learned
apart and only recombined when an arrival time is wanted:

  pace  seconds per metre while rolling; scales with distance. Stored as pace,
        not speed, because paces can be averaged and added
  hold  seconds standing per crossing; charged to the place, scales with nothing

Time to cross a cell is length x pace + hold. Both are learned in three nested
layers that back off downwards - cell (100 m of one shape), corridor (120 m
ground square plus heading, pooled across routes), global - each with a fast and
a slow exponentially weighted mean.

Pace is learned as a multiplier on the pace the timetable implies for that cell
at that hour, so the layers only explain what the timetable got wrong. Hold has
no prior and is learned in seconds from zero.
"""
import datetime

import numpy as np

from . import boost, config, layover, localtime

PACE_CLIP = (0.020, 2.0)     # s/m: 180 km/h .. 1.8 km/h while actually rolling
HOLD_CLIP = (0.0, 240.0)     # s standing per crossing
RATIO_CLIP = (0.15, 8.0)     # observed pace over timetabled pace
PACE0 = 1 / 7.0              # s/m, fallback where the timetable says nothing
SLOTS = 24                   # timetable prior resolution: one slot per hour
EXP_CAP = 700.0              # the largest exponent np.exp takes without overflowing


def decay(age, tau):
    """Weight left after `age` s of exponential decay with time constant
    `tau`; an infinite age gives zero."""
    return np.exp(-np.minimum(age / tau, EXP_CAP))


def between_slots(table, k):
    """The hourly `table` at fractional hour `k`, interpolated, so it does not
    jump on the hour."""
    i, f = int(k), k - int(k)
    return (1.0 - f) * table[i] + f * table[(i + 1) % SLOTS]


def group(keys, vals, weights):
    """Collapse repeated keys into one weighted mean each.

    Fancy-index assignment keeps only the last of a repeated index, so repeats
    must be combined first. Zero-weight entries are dropped, not averaged.
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
        """Weight left from an observation made at t; t = -inf gives zero."""
        return decay(now - t, self.tau)

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
    """One quantity, learned at unit / corridor / global scale.

    `prof_hl` is not a term but a back-off target sitting between the corridor
    and the unit, none if 0.0: one number per unit per hour of the day.
    """

    def __init__(self, nunit, ncorr, unit_corr, init, fast_hl, slow_hl,
                 k_unit=4.0, k_corr=4.0, prof_hl=0.0, nslot=SLOTS):
        self.unit_corr = unit_corr
        self.k_unit, self.k_corr = k_unit, k_corr
        self.cf = Ewma(nunit, fast_hl, init)
        self.cs = Ewma(nunit, slow_hl, init)
        self.rf = Ewma(ncorr, fast_hl, init)
        self.rs = Ewma(ncorr, slow_hl, init)
        self.pr = [Ewma(nunit, prof_hl, init) for _ in range(nslot)] \
            if prof_hl else None
        self.g = Ewma(1, slow_hl, init)

    def _cells(self):
        return self.cf, self.cs

    def _corrs(self):
        return self.rf, self.rs

    def update(self, units, vals, now, weights, corr, slot=0):
        total = weights.sum()
        if total <= 0.0:
            return
        for ewma in self._cells():
            ewma.update(units, vals, now, weights)
        if self.pr is not None:
            self.pr[slot].update(units, vals, now, weights)
        cu, vu, wu = corr
        for ewma in self._corrs():
            ewma.update(cu, vu, now, wu)
        self.g.update(np.zeros(1, dtype=int),
                      np.array([np.average(vals, weights=weights)]),
                      now, np.array([total]))

    def _blend(self, now, layers, base, k):
        num, den = base * k, float(k)
        for ewma in layers:
            m, w = ewma.read(now)
            num, den = num + m * w, den + w
        return num / den

    def read(self, now, slot=0):
        gm, _ = self.g.read(now)
        corr = self._blend(now, self._corrs(), gm[0], self.k_corr)
        base = corr[self.unit_corr]
        if self.pr is not None:
            base = self._blend(now, (self.pr[slot],), base, self.k_unit)
        return self._blend(now, self._cells(), base, self.k_unit)


class PaceModel:
    """Geometry, timetable prior and ETA arithmetic around the two quantities,
    each a `Layer`: three layers, two half-lives."""

    def __init__(self, net, cfg=None):
        self.cfg = cfg = cfg or config.FULL
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

        # what a travel time is learned per: every cell its own
        self.unit = np.arange(self.ncell)
        self.nunit = self.ncell
        self.unit_len = self.cell_len
        self.unit_corr = self.cell_corr

        self.prior = self._schedule_prior()
        if cfg.prior == "shape":
            self.prior = self.prior * (PACE0 / self._level(self.prior))

        self._cum = np.zeros(self.ncell + 1)
        self._prior_t = None
        self._per_cell = self.prior[0] * self.cell_len
        self.emitting = False   # set by the replay: is this epoch being scored
        self.layovers = layover.Layovers(net, localtime.TZ)
        self.boost = boost.Boost(net, localtime.TZ)
        self.pace = self._layer(1.0)
        self.hold = self._layer(0.0)

    def _level(self, prior):
        """The one number a whole prior array is worth: its length-weighted mean.

        One scalar across all slots, so rescaling by it moves the level and
        leaves the map and the time-of-day pattern alone.
        """
        return float(np.average(prior, weights=np.broadcast_to(
            self.cell_len, prior.shape)))

    def _schedule_prior(self):
        """Timetabled pace for every cell, at every hour of the day.

        This is an effective pace: it includes scheduled dwell, which is why hold
        starts at zero. Trips whose scheduled gaps are all identical are
        placeholders and are skipped. A cell with no timings at an hour falls
        back to its all-day mean, and one with none at all to PACE0.
        """
        num = np.zeros((SLOTS, self.ncell))
        slot_s = localtime.DAY_S / SLOTS
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
                    by_slot.setdefault(int(sched[0] // slot_s) % SLOTS, []).append(dt)
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

    @staticmethod
    def _hours(now):
        """The local time of day as a fractional hour."""
        return localtime.hours(datetime.datetime.fromtimestamp(now, localtime.TZ))

    def slot(self, now):
        return int(self._hours(now))

    def prior_at(self, now):
        """The timetabled pace of every cell at this instant.

        Hours are interpolated, not stepped, so the prior does not jump on the
        hour.
        """
        if now != self._prior_t:
            self._prior_row = between_slots(self.prior, self._hours(now))
            self._prior_t = now
        return self._prior_row

    def observe(self, cells, dist, pace, hold, hold_w, now):
        """Record cell crossings, finished or still in progress.

        An in-progress crossing carries only the fraction of its weight earned so
        far; the rest arrives when it finishes.
        """
        cells = np.asarray(cells)
        held = np.clip(hold, *HOLD_CLIP)
        ratio = np.clip(pace / self.prior_at(now)[cells], *RATIO_CLIP)
        units = self.unit[cells]
        self._absorb(units, self.cell_corr[cells], ratio, held,
                     dist / self.unit_len[units], hold_w, now)

    def expected(self, cells):
        """Seconds a crossing of these cells is currently believed to take."""
        return self._per_cell[cells]

    def _apply(self, ratio, hold, now):
        """Cumulative travel time along every shape, so an ETA is a subtraction.

        `ratio` and `hold` are per unit and are spread to that unit's cells; this
        is where the timetable prior re-enters.
        """
        self._pace = ratio[self.unit] * self.prior_at(now)
        self._hold = hold[self.unit]
        self._per_cell = self._pace * self.cell_len + self._hold
        np.cumsum(self._per_cell, out=self._cum[1:])

    def integrate(self, shape_id, d0, d1, per_cell=None, cum=None):
        """Integrate a per-cell quantity along a shape, from d0 to d1.

        Defaults to travel time. `cum` is the running sum of `per_cell` with a
        leading zero, as `_apply` builds it.
        """
        per_cell = self._per_cell if per_cell is None else per_cell
        cum = self._cum if cum is None else cum
        s = self.net.shapes[shape_id]
        b = self.shape_base[shape_id]
        cl = s.length / s.cells

        def upto(d):
            d = np.clip(np.asarray(d, dtype=float), 0.0, s.length)
            i = np.minimum((d / cl).astype(int), s.cells - 1)
            return cum[b + i] - cum[b] + (d / cl - i) * per_cell[b + i]

        return np.maximum(upto(d1) - upto(d0), 0.0)

    def time_between(self, shape_id, d0, d1):
        """Seconds to go from d0 to d1 metres along a shape (vectorised in d1)."""
        return self.integrate(shape_id, d0, d1)


    def _layer(self, init):
        """One `Layer` of the two, pace or hold."""
        return Layer(self.nunit, self.ncorr, self.unit_corr, init,
                     self.cfg.fast_hl, self.cfg.slow_hl,
                     k_unit=self.cfg.k_unit, k_corr=self.cfg.k_corr,
                     prof_hl=self.cfg.prof_hl)

    def _absorb(self, units, corr, ratio, held, w_pace, w_hold, now):
        slot = self.slot(now)
        self.pace.update(units, ratio, now, w_pace, group(corr, ratio, w_pace),
                         slot)
        self.hold.update(units, held, now, w_hold, group(corr, held, w_hold),
                         slot)

    def refresh(self, now):
        slot = self.slot(now)
        self._apply(self.pace.read(now, slot), self.hold.read(now, slot), now)
