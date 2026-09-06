"""Sweep one estimator constant at a time and write down what each value scored.

Separate from `experiments.py` because it answers a different question. That one
asks whether a design decision is worth making; this one asks what number to set
once the decision is made. Mixing them would bury nine readable variants under
forty points of a grid.

The method is otherwise identical: every point is a cold replay of the same
recording, scored against the same ground truth, on the predictions every point
in the sweep answered. Only the swept field differs from the base approach, so a
difference in the score is a difference in that field or it is noise - which is
why the 95% interval is printed next to every value and not left in a file.

The base is `full` unless `--base` says otherwise, and a constant's best value
is not the same on every base: what a shrinkage constant wants depends on what
it is shrinking towards.

    python3 -m lvivpred sweep k_unit 1 2 4 8 16
    python3 -m lvivpred sweep k_unit --base sections-no-prior
"""
import json
import os
from dataclasses import replace

import numpy as np

from . import config, network, replay, score
from .experiments import REPORTS, _end

# The constants worth sweeping, and the values worth trying. Anything in Config
# can be swept by name; these are the ones with a reason behind them.
GRIDS = {
    "k_unit": [0.5, 1.0, 2.0, 4.0, 8.0, 16.0],
    # `k_corr` stayed monotone to its lower edge even after the grid was
    # extended there, but the whole range spans under 2 s of MAE. It is a nearly
    # flat direction; the grid is kept for completeness, not for a decision.
    "k_corr": [0.125, 0.25, 0.5, 1.0, 2.0, 4.0],
    # Both half-life grids ran to their upper edge on the first recording, so
    # both now extend past the length of a day, where decay stops meaning much.
    # On the second pass both turned over inside these ranges.
    "fast_hl": [480.0, 1800.0, 7200.0, 14400.0, 28800.0, 57600.0],
    "slow_hl": [5400.0, 43200.0, 172800.0, 345600.0, 691200.0],
    "knn": [3, 5, 10, 20, 40],
}


def run(field, values=None, net=None, out=REPORTS, db=replay.DB, base=None, **kw):
    net = net or network.load()
    base = base or config.FULL
    values = values or GRIDS[field]
    if not hasattr(base, field):
        raise SystemExit(f"Config has no field {field!r}; "
                         f"try one of {', '.join(GRIDS)}")
    if field == "knn" and base.learn != "knn":
        raise SystemExit(f"`{base.name}` does not use knn, so every point of "
                         f"this sweep would replay the same model; --base knn")
    # The CLI cannot know whether a grid is over counts or over seconds, so the
    # field itself says: a ring buffer indexed by a float is not an index.
    cast = type(getattr(base, field))
    kw.setdefault("t_to", _end(db))

    cfgs = [replace(base, name=f"{field}={v:g}", **{field: v})
            for v in map(cast, values)]
    named, truth, rec = replay.run_many(net, cfgs, db=db, **kw)

    paired = score.common(named)
    rows = {n: score.stats(s.error) for n, s in paired.items()}
    ref = paired[min(rows, key=lambda n: rows[n]["mae"])]
    data = {"field": field, "base": base.name, "values": list(values),
            "crossings": truth.n, "epochs": rec.epochs, "overall": rows,
            "ci": {n: [float(x) for x in
                       score.bootstrap(np.abs(s.error), truth.trip[s.event])]
                   for n, s in paired.items()},
            "vs_best": {n: _paired_ci(s, ref, truth) for n, s in paired.items()}}

    os.makedirs(out, exist_ok=True)
    path = os.path.join(out, "sweeps.json")
    all_sweeps = {}
    if os.path.exists(path):
        with open(path) as f:
            all_sweeps = json.load(f)
    # Keyed by base too: the same grid on a different starting point is a
    # different sweep and must not silently replace the one before it.
    all_sweeps[field if base.name == "full" else f"{field}@{base.name}"] = data
    with open(path, "w") as f:
        json.dump(all_sweeps, f, indent=1)

    _print(data)
    return data


def _paired_ci(s, ref, truth):
    """95% interval on how much worse this point is than the best one.

    Every point answered the same rows in the same order, so the difference can
    be resampled row by row rather than each MAE separately. That removes the
    variance the two have in common - which on a grid this tight is nearly all
    of it - and is the difference between a readable sweep and six overlapping
    intervals. An interval that straddles zero means the grid did not separate
    those two values on this recording.
    """
    lo, hi = score.bootstrap(np.abs(s.error) - np.abs(ref.error),
                             truth.trip[s.event])
    return [float(lo), float(hi)]


def _print(d):
    best = min(d["overall"], key=lambda n: d["overall"][n]["mae"])
    print(f"\n{d['field']} on `{d['base']}`, scored on the common support "
          f"({d['crossings']} crossings, {d['epochs']} epochs)\n")
    print(f"  {'value':<16} {'MAE s':>7} {'median':>7} {'bias':>7}"
          f"  {'MAE - best, 95%':>20}")
    for n, r in d["overall"].items():
        lo, hi = d["vs_best"][n]
        sep = "" if n == best else ("   separated" if lo > 0 else "   not separated")
        print(f"  {n:<16} {r['mae']:7.1f} {r['median']:7.1f} {r['bias']:+7.1f}"
              f"  {f'[{lo:+.1f}, {hi:+.1f}]':>20}"
              f"{'   <- best' if n == best else sep}")
