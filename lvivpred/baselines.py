"""Estimators that exist to bound what the one in `model.py` is worth.

Two of the shipped model's claims are expensive: that learning has to happen
online as fixes arrive, and that the cell / corridor / global back-off is worth
its complexity. Each gets an estimator here that denies it, so the claim can be
priced instead of argued about.

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

Table fitting happens during the replay's own warmup and stops the instant scoring
starts, so the split is structural rather than remembered: `replay` sets
`emitting` on the model at the first epoch it scores, and after that the table
takes no more evidence. Run those variants with a warmup long enough to be a
training window - an evening, say, scored the next morning. `knn` learns online
like the shipped model and needs no such split.
"""
import numpy as np

from .model import SLOTS, BaseModel, Ewma, group


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
