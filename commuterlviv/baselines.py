"""Estimators that exist to bound what the one in `model.py` is worth.

Three of the shipped model's claims are expensive: that learning has to happen
online as fixes arrive, that the cell / corridor / global back-off is worth its
complexity, and that a mean is the right summary of what a road has been doing.
Each gets an estimator here that denies it, so the claim can be priced instead
of argued about.

  table       one travel time per (section, hour), fitted once and frozen. If
              this matches the live model, online learning is doing nothing a
              lookup could not.
  table-live  the same table times one global number tracking whether today as
              a whole runs faster or slower than it. One online parameter, so
              whatever separates it from `table` is the value of knowing today
              is slow and nothing else.
  knn         the median of the last k crossings of this unit by any vehicle.
              No hierarchy, no decay curve, one constant. If this matches the
              live model, the back-off structure is not earning its keep.
  median      the full hierarchy and the full decay, with every mean replaced by
              a weighted median. Differs from the shipped model in the loss it
              optimises and in nothing else, which is the point: MAE is
              minimised by the median, and the shipped model is means throughout.

Table fitting happens during the replay's own warmup and stops the instant scoring
starts, so the split is structural rather than remembered: `replay` sets
`emitting` on the model at the first epoch it scores, and after that the table
takes no more evidence. Run those variants with a warmup long enough to be a
training window - an evening, say, scored the next morning. `knn` and `median`
learn online like the shipped model and need no such split.
"""
import numpy as np

from .model import SLOTS, BaseModel, Ewma, PaceModel, group


class TableModel(BaseModel):
    """One pace ratio and one hold per (unit, hour of day), fitted then frozen.

    Stored as a sum and a weight rather than a mean, so a cell seen twice at
    eight in the morning and never at nine can back off to its own all-day mean
    at nine, and a cell never seen at all can back off to the city. That is the
    same shrinkage the live model does across space, done here across time,
    and it uses the same constant: `k_unit` observations before a slot's own
    evidence outweighs what it backs off to.
    """

    def __init__(self, net, cfg=None):
        super().__init__(net, cfg)
        shape = (SLOTS, self.nunit)
        self.pace_num, self.pace_den = np.zeros(shape), np.zeros(shape)
        self.hold_num, self.hold_den = np.zeros(shape), np.zeros(shape)
        self.live = (Ewma(1, self.cfg.fast_hl, 1.0)
                     if self.cfg.learn == "table-live" else None)
        self._table = None

    def _absorb(self, units, corr, ratio, held, w_pace, w_hold, now):
        if not self.emitting:
            self._table = None
            slot = self._slot(now)
            np.add.at(self.pace_num[slot], units, ratio * w_pace)
            np.add.at(self.pace_den[slot], units, w_pace)
            np.add.at(self.hold_num[slot], units, held * w_hold)
            np.add.at(self.hold_den[slot], units, w_hold)
        elif self.live is not None and w_pace.sum() > 0.0:
            # How far today has drifted from the table, as one number. The
            # table's own prediction is the denominator, so a section the table
            # already knows is slow does not count as today being slow.
            pace, _ = self._frozen()
            want = pace[self._slot(now), units]
            self.live.update(np.zeros(1, dtype=int),
                             np.array([np.average(ratio / want, weights=w_pace)]),
                             now, np.array([w_pace.sum()]))

    def _frozen(self):
        """The fitted table, shrunk towards the all-day mean and the city.

        Computed once and cached: after fitting ends nothing in it moves again,
        and it is read every epoch.
        """
        if self._table is None:
            self._table = (self._shrink(self.pace_num, self.pace_den, 1.0),
                           self._shrink(self.hold_num, self.hold_den, 0.0))
        return self._table

    def _shrink(self, num, den, init):
        k = self.cfg.k_unit
        g = num.sum() / den.sum() if den.sum() > 0 else init
        allday = (num.sum(axis=0) + k * g) / (den.sum(axis=0) + k)
        return (num + k * allday) / (den + k)

    def refresh(self, now):
        pace, hold = self._frozen()
        k = self._hours(now)
        ratio = self._between(pace, k)
        if self.live is not None:
            ratio = ratio * self.live.read(now)[0][0]
        self._apply(ratio, self._between(hold, k), now)

    @staticmethod
    def _between(table, k):
        """The table at a fractional hour, interpolated the way the prior is."""
        i, f = int(k), k - int(k)
        return (1.0 - f) * table[i] + f * table[(i + 1) % SLOTS]


class KnnModel(BaseModel):
    """The median of the last k things that happened here, and nothing else.

    A ring buffer per unit, k wide. No corridor, no global, no half-life: a unit
    is exactly as current as its last k crossings, which on a busy street is
    minutes and on a quiet one is hours. That is the crude version of what the
    two half-lives do properly, and the point is to find out how much the proper
    version is worth.

    Median rather than mean because MAE is minimised by the median, so this also
    answers the second question in one go: whether the shipped model, which is
    means throughout, is optimising the wrong loss.

    A unit with an empty buffer predicts a ratio of 1, which is the timetable's
    own pace where there is a prior and the fallback pace where there is not.
    """

    def __init__(self, net, cfg=None):
        super().__init__(net, cfg)
        k = self.cfg.knn
        self.pace = np.ones((self.nunit, k))
        self.hold = np.zeros((self.nunit, k))
        self.n_pace = np.zeros(self.nunit, dtype=np.int64)
        self.n_hold = np.zeros(self.nunit, dtype=np.int64)

    def _absorb(self, units, corr, ratio, held, w_pace, w_hold, now):
        # One entry per unit per batch, not per crossing: within a single epoch
        # the same unit is often reported by several vehicles at once, and the
        # buffer is meant to hold the last k moments, not the last k vehicles.
        # The two buffers advance separately because a crossing can carry pace
        # without carrying any evidence about standing time.
        self._push(self.pace, self.n_pace, *group(units, ratio, w_pace))
        self._push(self.hold, self.n_hold, *group(units, held, w_hold))

    @staticmethod
    def _push(buf, seen, u, val, _w):
        buf[u, seen[u] % buf.shape[1]] = val
        seen[u] += 1

    def refresh(self, now):
        k = self.cfg.knn
        self._apply(self._median(self.pace, np.minimum(self.n_pace, k), 1.0),
                    self._median(self.hold, np.minimum(self.n_hold, k), 0.0),
                    now)

    @staticmethod
    def _median(buf, n, empty):
        """Median of the first n entries of each row, or `empty` where n is 0.

        Sorting the unwritten tail with the rest would drag every short row
        towards whatever it was initialised to, so the tail is pushed to +inf
        and the median taken by index instead of by numpy's own rule.
        """
        a = np.where(np.arange(buf.shape[1]) < n[:, None], buf, np.inf)
        a.sort(axis=1)
        rows = np.arange(len(n))
        lo, hi = np.maximum(n - 1, 0) // 2, np.maximum(n, 1) // 2
        return np.where(n > 0, 0.5 * (a[rows, lo] + a[rows, hi]), empty)


class Ring:
    """The last m observations per key, with their weights and their times.

    An EWMA can carry a mean in one number because a mean of a mean is a mean.
    A median cannot: it needs the observations themselves. So each key keeps a
    fixed window of the last m, overwriting oldest-first, and decay is applied
    when the window is read rather than when it is written.

    m is a memory the half-lives cannot see past. A cell crossed 11.5 times a
    day with m = 16 holds most of a day, which is the slow term's reach; a busy
    corridor holds minutes, which is the fast term's. That mismatch is real and
    is the price of medians, not a bug to hide - it is one of the things the
    comparison is measuring.
    """

    def __init__(self, n, m, init, fast_tau, slow_tau, fast=True):
        self.val = np.full((n, m), float(init))
        self.w = np.zeros((n, m))
        self.t = np.full((n, m), -np.inf)
        self.at = np.zeros(n, dtype=np.int64)
        self.taus = (fast_tau, slow_tau) if fast else (slow_tau,)

    def update(self, idx, vals, now, weights):
        idx, vals, weights = group(idx, vals, weights)
        if not len(idx):
            return
        slot = self.at[idx] % self.val.shape[1]
        self.val[idx, slot] = vals
        self.w[idx, slot] = weights
        self.t[idx, slot] = now
        self.at[idx] += 1

    def weights(self, now):
        """Each stored weight, faded by however long ago it was stored.

        Two half-lives are one kernel here rather than two estimators blended
        afterwards: an observation counts for the mean of what the short memory
        and the long memory each still make of it. Blending two medians would
        not be a median of anything.
        """
        age = now - self.t
        left = sum(np.exp(-np.minimum(age / tau, 700.0)) for tau in self.taus)
        return self.w * left / len(self.taus)


def wmedian(val, w):
    """The weighted median of each row, interpolated between the two middles.

    Each sorted entry is placed at the middle of the weight it occupies, and the
    answer is read off at half the total by straight interpolation between the
    two entries either side. Simply returning the entry where the cumulative
    weight first passes half is the other common definition and it is biased: it
    always returns the lower of two middles, which on an even count is half a
    spacing low every time. Measured on this recording that convention cost 79
    seconds of bias, so the interpolation is not a nicety.

    With equal weights this reproduces `np.median` exactly. A slot never written
    carries no weight and is sorted to +inf so it can never be interpolated
    towards; the crossing always lands at or before the last entry that has
    weight, which is why that is safe. Rows must carry weight somewhere, which
    the back-off entry in `MedianLayer` guarantees.
    """
    o = np.argsort(np.where(w > 0.0, val, np.inf), axis=1, kind="stable")
    vs, ws = np.take_along_axis(val, o, 1), np.take_along_axis(w, o, 1)
    cum = np.cumsum(ws, axis=1)
    pos = (cum - 0.5 * ws) / np.maximum(cum[:, -1:], 1e-12)

    rows = np.arange(len(val))
    j = np.clip((pos < 0.5).sum(axis=1), 1, val.shape[1] - 1)
    p0, p1 = pos[rows, j - 1], pos[rows, j]
    v0, v1 = vs[rows, j - 1], vs[rows, j]
    f = np.clip((0.5 - p0) / np.maximum(p1 - p0, 1e-12), 0.0, 1.0)
    return v0 + f * (v1 - v0)


class MedianLayer:
    """`model.Layer`, with every mean replaced by a weighted median.

    The back-off is the same three levels and the same two constants, expressed
    the way a median can express it: the level above enters as one more
    observation carrying weight k. With no local evidence the median of that row
    is the parent's value, exactly as the mean version returns the parent; with
    plenty, the parent is one point among many and is outvoted. The mean version
    blends continuously and this one switches over, which is the second thing
    the comparison measures.
    """

    def __init__(self, nunit, ncorr, unit_corr, init, fast_hl, slow_hl, m,
                 k_unit=4.0, k_corr=4.0, fast=True, corridor=True):
        self.unit_corr = unit_corr
        self.corridor = corridor
        self.k_unit, self.k_corr = k_unit, k_corr
        args = (m, init, fast_hl / np.log(2.0), slow_hl / np.log(2.0))
        self.cell = Ring(nunit, *args, fast=fast)
        self.corr = Ring(ncorr, *args, fast=fast)
        self.glob = Ring(1, *args, fast=fast)

    # `slot` is accepted and ignored: it picks the time-of-day row of the
    # profile ring, which this layer does not have - the comparison is about
    # mean against median, so it stays at the two levels both versions share.
    def update(self, units, vals, now, weights, corr, slot=0):
        total = weights.sum()
        if total <= 0.0:
            return
        self.cell.update(units, vals, now, weights)
        if self.corridor:
            cu, vu, wu = corr
            self.corr.update(cu, vu, now, wu)
        # One entry per batch, summarising the batch the way this layer
        # summarises everything - so the global row is a median of medians.
        self.glob.update(np.zeros(1, dtype=int),
                         np.array([np.median(vals)]), now, np.array([total]))

    @staticmethod
    def _with_parent(ring, now, parent, k):
        val = np.concatenate([ring.val, parent[:, None]], axis=1)
        w = np.concatenate([ring.weights(now), np.full((len(parent), 1), k)],
                           axis=1)
        return wmedian(val, w)

    def read(self, now, slot=0):
        glob = float(wmedian(self.glob.val, self.glob.weights(now))[0])
        if self.corridor:
            corr = self._with_parent(self.corr, now,
                                     np.full(len(self.corr.val), glob),
                                     self.k_corr)
            base = corr[self.unit_corr]
        else:
            base = np.full(len(self.cell.val), glob)
        return self._with_parent(self.cell, now, base, self.k_unit)


class MedianModel(PaceModel):
    """The shipped model with `MedianLayer` in place of `model.Layer`.

    Everything else is inherited, which is the claim being tested: the two
    differ in how a layer summarises what it has seen, and in nothing else.
    """

    def _layer(self, init):
        return MedianLayer(self.nunit, self.ncorr, self.unit_corr, init,
                           self.cfg.fast_hl, self.cfg.slow_hl, self.cfg.ring,
                           k_unit=self.cfg.k_unit, k_corr=self.cfg.k_corr,
                           fast=self.cfg.fast, corridor=self.cfg.corridor)
