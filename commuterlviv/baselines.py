"""Estimators that bound what the model in `model.py` is worth.

  table       one travel time per (section, hour), fitted once and frozen
  table-live  that table times one global number for how today is running
  knn         the median of the last k crossings of this unit, no hierarchy
  median      the full hierarchy with every mean replaced by a weighted median

Table fitting runs during the replay warmup and stops when `replay` sets
`emitting`, so those variants need a warmup long enough to be a training window.
"""
import numpy as np

from .model import SLOTS, BaseModel, Ewma, PaceModel, group


class TableModel(BaseModel):
    """One pace ratio and one hold per (unit, hour of day), fitted then frozen.

    Kept as sum and weight, not a mean, so a thin slot can shrink towards the
    unit's all-day mean and then towards the city, with `k_unit` as the constant.
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
            # the table's own prediction is the denominator, so a section the
            # table already knows is slow does not count as today being slow
            pace, _ = self._frozen()
            want = pace[self._slot(now), units]
            self.live.update(np.zeros(1, dtype=int),
                             np.array([np.average(ratio / want, weights=w_pace)]),
                             now, np.array([w_pace.sum()]))

    def _frozen(self):
        """The fitted table, shrunk towards the all-day mean and the city."""
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
    """The median of the last k crossings of a unit: no corridor, no global, no
    half-life. An empty buffer predicts a ratio of 1."""

    def __init__(self, net, cfg=None):
        super().__init__(net, cfg)
        k = self.cfg.knn
        self.pace = np.ones((self.nunit, k))
        self.hold = np.zeros((self.nunit, k))
        self.n_pace = np.zeros(self.nunit, dtype=np.int64)
        self.n_hold = np.zeros(self.nunit, dtype=np.int64)

    def _absorb(self, units, corr, ratio, held, w_pace, w_hold, now):
        # one entry per unit per batch, not per crossing: the buffer holds the
        # last k moments, not the last k vehicles
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

        The unwritten tail is pushed to +inf and the median taken by index, so
        short rows are not dragged towards their initial value.
        """
        a = np.where(np.arange(buf.shape[1]) < n[:, None], buf, np.inf)
        a.sort(axis=1)
        rows = np.arange(len(n))
        lo, hi = np.maximum(n - 1, 0) // 2, np.maximum(n, 1) // 2
        return np.where(n > 0, 0.5 * (a[rows, lo] + a[rows, hi]), empty)


class Ring:
    """The last m observations per key, with their weights and their times.

    A median needs the observations themselves, so each key keeps a window of the
    last m, overwriting oldest-first, and decay is applied on read. m bounds the
    memory regardless of the half-lives.
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

        The two half-lives are one kernel, not two blended estimators: a blend of
        two medians is not a median.
        """
        age = now - self.t
        left = sum(np.exp(-np.minimum(age / tau, 700.0)) for tau in self.taus)
        return self.w * left / len(self.taus)


def wmedian(val, w):
    """The weighted median of each row, interpolated between the two middles.

    Interpolating matters: taking the entry where cumulative weight first passes
    half is biased low on an even count. With equal weights this equals
    `np.median`. Unwritten slots carry no weight and sort to +inf, so they are
    never interpolated towards; every row must carry weight somewhere, which
    `MedianLayer`'s back-off entry guarantees.
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

    Same three levels and two constants; the level above enters as one more
    observation carrying weight k.
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

    # `slot` is accepted and ignored: this layer has no profile ring
    def update(self, units, vals, now, weights, corr, slot=0):
        total = weights.sum()
        if total <= 0.0:
            return
        self.cell.update(units, vals, now, weights)
        if self.corridor:
            cu, vu, wu = corr
            self.corr.update(cu, vu, now, wu)
        # one entry per batch, so the global row is a median of medians
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
    """The shipped model with `MedianLayer` in place of `model.Layer`."""

    def _layer(self, init):
        return MedianLayer(self.nunit, self.ncorr, self.unit_corr, init,
                           self.cfg.fast_hl, self.cfg.slow_hl, self.cfg.ring,
                           k_unit=self.cfg.k_unit, k_corr=self.cfg.k_corr,
                           fast=self.cfg.fast, corridor=self.cfg.corridor)
