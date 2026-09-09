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

from . import config

PACE_CLIP = (0.020, 2.0)     # s/m: 180 km/h .. 1.8 km/h while actually rolling
HOLD_CLIP = (0.0, 240.0)     # s standing per crossing
RATIO_CLIP = (0.15, 8.0)     # observed pace over timetabled pace
PACE0 = 1 / 7.0              # s/m, fallback where the timetable says nothing
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
    """One quantity, learned at unit / corridor / global scale.

    A unit is whatever travel time is learned per - a 100 m cell by default.
    Either of the two upper layers can be switched off, in which case the one
    below simply backs off further; there is always the global number.

    A third half-life, `day_hl`, is optional and measured in days. Its term sits
    beside the other two at both scales, so what a cell learned yesterday still
    carries weight this morning instead of the model waking onto the prior.
    """

    def __init__(self, nunit, ncorr, unit_corr, init, fast_hl, slow_hl,
                 k_unit=4.0, k_corr=4.0, fast=True, corridor=True, day_hl=0.0):
        self.unit_corr = unit_corr
        self.fast, self.corridor = fast, corridor
        self.k_unit, self.k_corr = k_unit, k_corr
        self.cf = Ewma(nunit, fast_hl, init)
        self.cs = Ewma(nunit, slow_hl, init)
        self.rf = Ewma(ncorr, fast_hl, init)
        self.rs = Ewma(ncorr, slow_hl, init)
        self.cd = Ewma(nunit, day_hl, init) if day_hl else None
        self.rd = Ewma(ncorr, day_hl, init) if day_hl else None
        self.g = Ewma(1, slow_hl, init)

    def _cells(self):
        return ((self.cf,) if self.fast else ()) + (self.cs,) + \
            ((self.cd,) if self.cd is not None else ())

    def _corrs(self):
        return ((self.rf,) if self.fast else ()) + (self.rs,) + \
            ((self.rd,) if self.rd is not None else ())

    def update(self, units, vals, now, weights, corr):
        total = weights.sum()
        if total <= 0.0:
            return
        for ewma in self._cells():
            ewma.update(units, vals, now, weights)
        if self.corridor:
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

    def read(self, now):
        gm, _ = self.g.read(now)
        if self.corridor:
            corr = self._blend(now, self._corrs(), gm[0], self.k_corr)
            base = corr[self.unit_corr]
        else:
            base = gm[0]
        return self._blend(now, self._cells(), base, self.k_unit)


class BaseModel:
    """Everything an estimator needs that is not the estimating.

    The geometry - which cells belong to which shape, how long each is, which
    corridor and which unit it falls in - is the same whatever learns on top of
    it, and so is the timetable prior and the arithmetic that turns a pace into
    an arrival time. Only two things differ between the families in this project
    and in `baselines.py`: what a subclass does with an observation (`_absorb`)
    and where it gets a ratio and a hold from when asked (`refresh`).

    Keeping the split here is what makes the comparison honest. Two estimators
    that share this class cannot differ in their geometry, their prior or their
    ETA arithmetic even by accident, so a difference in the score is a
    difference in the learning.
    """

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

        self.unit = (self._sections() if cfg.unit == "section"
                     else np.arange(self.ncell))
        self.nunit = int(self.unit.max()) + 1
        self.unit_len = np.bincount(self.unit, self.cell_len, self.nunit)
        self.unit_corr = np.zeros(self.nunit, dtype=np.int64)
        self.unit_corr[self.unit] = self.cell_corr

        self.prior = (np.full((SLOTS, self.ncell), PACE0) if cfg.prior == "off"
                      else self._schedule_prior())
        if cfg.prior == "shape":
            self.prior = self.prior * (PACE0 / self._level(self.prior))

        self._cum = np.zeros(self.ncell + 1)
        self._prior_t = None
        self._per_cell = self.prior[0] * self.cell_len
        # Set by the replay at every epoch: whether this one is being scored.
        # Only an estimator that stops learning when scoring starts reads it.
        self.emitting = False

    def _level(self, prior):
        """The one number a whole prior array is worth: its length-weighted mean.

        Length-weighted because a pace is a cost per metre, so the average the
        city actually experiences is the one where a 400 m cell counts four
        times a 100 m one. One scalar for all 24 slots, not one per slot, so
        rescaling by it moves the level and leaves both the map and the
        time-of-day pattern exactly as they were.
        """
        return float(np.average(prior, weights=np.broadcast_to(
            self.cell_len, prior.shape)))

    def _sections(self):
        """Map every cell to the stop-to-stop section it falls in.

        Sections are cut where the stops are, so a shape served by more than one
        stop pattern has to pick one; the pattern running the most trips on that
        shape wins. Cells before the first stop or after the last join the
        section next to them.
        """
        seen = {}
        for trip, key in self.net.pattern_of.items():
            n, _ = seen.get(key, (0, None))
            seen[key] = (n + 1, trip)
        best = {}
        for (sid, _), (n, trip) in seen.items():
            if n > best.get(sid, (0, None))[0]:
                best[sid] = (n, trip)

        out = np.zeros(self.ncell, dtype=np.int64)
        nxt = 0
        for sid, b in self.shape_base.items():
            s = self.net.shapes[sid]
            if sid not in best:
                k = np.arange(s.cells)       # no pattern here: leave it as cells
            else:
                edges = self.net.trip_stops[best[sid][1]][1]
                centre = (np.arange(s.cells) + 0.5) * (s.length / s.cells)
                k = np.clip(np.searchsorted(edges, centre) - 1,
                            0, max(len(edges) - 2, 0))
            out[b:b + s.cells] = nxt + k
            nxt += int(k.max()) + 1
        return out

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

    @staticmethod
    def _hours(now):
        """The local time of day as a fractional hour."""
        local = datetime.datetime.fromtimestamp(now, TZ)
        return local.hour + local.minute / 60.0

    def _slot(self, now):
        return int(self._hours(now))

    def prior_at(self, now):
        """The timetabled pace of every cell at this instant.

        Hours are interpolated rather than stepped: a prediction made at 08:55
        for an arrival at 09:10 would otherwise be built entirely out of the
        eight o'clock timetable and jump when the clock ticked over.
        """
        if now != self._prior_t:
            k = self._hours(now)
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
        held = np.clip(hold, *HOLD_CLIP)
        if not self.cfg.hold:
            # One quantity instead of two: standing time is charged to the
            # distance it was spent over, and so scales with distance.
            pace = pace + held / np.maximum(dist, 1.0)
            held = np.zeros_like(held)
        ratio = np.clip(pace / self.prior_at(now)[cells], *RATIO_CLIP)
        units = self.unit[cells]
        self._absorb(units, self.cell_corr[cells], ratio, held,
                     dist / self.unit_len[units], hold_w, now)

    def expected(self, cells):
        """Seconds a crossing of these cells is currently believed to take."""
        return self._per_cell[cells]

    def _apply(self, ratio, hold, now):
        """Cumulative travel time along every shape, so an ETA is a subtraction.

        `ratio` and `hold` are per unit; everything downstream is per cell, and
        a unit wider than a cell simply hands the same number to each of its
        cells. Pace comes back as a multiple of the timetable's, so this is
        where the prior re-enters and where a subclass need not think about it.
        """
        self._pace = ratio[self.unit] * self.prior_at(now)
        self._hold = hold[self.unit]
        self._per_cell = self._pace * self.cell_len + self._hold
        np.cumsum(self._per_cell, out=self._cum[1:])

    def integrate(self, shape_id, d0, d1, per_cell=None, cum=None):
        """Integrate a per-cell quantity along a shape, from d0 to d1.

        Travel time is the case that matters and the default, but the residual
        features in `features.py` need the same integral over the model's own
        evidence weights, and the arithmetic of a partly-crossed cell is fiddly
        enough that it should exist in one place. `cum` is the running sum of
        `per_cell` with a leading zero, as `_apply` builds it.
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


class PaceModel(BaseModel):
    """The shipped estimator: two quantities, three layers, two half-lives."""

    def __init__(self, net, cfg=None):
        super().__init__(net, cfg)
        self.pace = self._layer(1.0)
        self.hold = self._layer(0.0)

    def _layer(self, init):
        """One layer of the two. The only thing `MedianModel` changes."""
        return Layer(self.nunit, self.ncorr, self.unit_corr, init,
                     self.cfg.fast_hl, self.cfg.slow_hl,
                     k_unit=self.cfg.k_unit, k_corr=self.cfg.k_corr,
                     fast=self.cfg.fast, corridor=self.cfg.corridor,
                     day_hl=self.cfg.day_hl)

    def _absorb(self, units, corr, ratio, held, w_pace, w_hold, now):
        self.pace.update(units, ratio, now, w_pace, group(corr, ratio, w_pace))
        self.hold.update(units, held, now, w_hold, group(corr, held, w_hold))

    def refresh(self, now):
        self._apply(self.pace.read(now), self.hold.read(now), now)
