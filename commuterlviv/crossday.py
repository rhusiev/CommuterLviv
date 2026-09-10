"""Score every day of the recording separately, so a conclusion drawn on one
day can be read against the next.

Every number in `reports/approaches.md` is pooled over the whole recording. That
was the only thing a one-day recording could say, and it hides the question the
comparison actually turns on: an online model that has seen a previous day is
not the same model as one that started this morning, and a variant that wins
pooled may be winning only the day it was cold on.

So this is one replay per variant over the whole recording - the models learn
across the nights exactly as they would in service - split afterwards by the
service day each prediction was *made* on. The first day is the cold one and is
labelled as such: nothing was carried into it, and it is the only day whose
score answers the same question the one-day comparison did.

The support is chosen once, over the whole recording, and then cut by day. That
matters: choosing it per day would let a variant be judged on a different set of
crossings on each day, and the days would stop being comparable to each other.

    python3 -m commuterlviv crossday
    python3 -m commuterlviv crossday --only full knn slow-day

Each day is a full working day of replay, so this is an overnight job like the
sweeps, not something to run between two questions.
"""
import json
import os

import numpy as np

from . import config, network, predictors, replay, score
from .experiments import REPORTS, _end

# The variants the plan's open questions hang on, rather than all of them: a
# multi-day replay costs a day of work per variant per day of recording.
DEFAULT = ("full", "no-prior", "knn", "tuned", "slow-day", "table")
MIN_N = 2000    # predictions a day needs before its MAE is worth printing


def run(variants=None, db=replay.DB, out=REPORTS, min_n=MIN_N, **kw):
    net = network.load()
    variants = variants or [config.BY_NAME[n] for n in DEFAULT]
    kw.setdefault("t_to", _end(db))

    named, truth, rec = replay.run_many(net, variants, db=db, **kw)
    named["api"] = predictors.api(rec, truth)
    named["schedule"] = predictors.schedule(rec, truth, net)
    paired = score.paired(named)

    days = {}
    for name, s in paired.items():
        _, day = score.clock(s.epoch)
        for d in np.unique(day):
            m = day == d
            if m.sum() >= min_n:
                row = score.stats(s.error[m])
                lo, hi = score.bootstrap(np.abs(s.error[m]),
                                         truth.trip[s.event[m]])
                row["ci"] = [float(lo), float(hi)]
                days.setdefault(d, {})[name] = row

    data = {"crossings": truth.n, "epochs": rec.epochs,
            "variants": [c.name for c in variants], "days": dict(sorted(days.items())),
            "overall": {n: score.stats(s.error) for n, s in paired.items()}}

    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "crossday.json"), "w") as f:
        json.dump(data, f, indent=1)
    with open(os.path.join(out, "crossday.md"), "w") as f:
        f.write(_markdown(data))
    _print(data)
    return data


def _print(d):
    for day, rows in d["days"].items():
        print(f"\n{day}, {len(rows)} approaches\n")
        for name in sorted(rows, key=lambda n: rows[n]["mae"]):
            r = rows[name]
            print(f"  {name:<16} {r['n']:>9} {r['mae']:>7.1f} s  "
                  f"[{r['ci'][0]:.1f}, {r['ci'][1]:.1f}]")


def _markdown(d):
    days = list(d["days"])
    names = sorted(d["overall"], key=lambda n: d["overall"][n]["mae"])
    out = ["# The same approaches, day by day", "",
           f"One replay per approach over the whole recording - "
           f"{d['crossings']} crossings, {d['epochs']} minutes - cut afterwards "
           "by the service day each prediction was made on. The models are not "
           "restarted at the day boundaries: whatever an online approach learns "
           "on one day it carries into the next, which is the point of the "
           "table.", "",
           f"**{days[0]} is the cold day.** Nothing was carried into it, so it "
           "is the only column that asks the question a one-day recording could "
           "ask. Read every later column against it: an approach whose lead "
           "disappears once the others have seen a day of the city was winning "
           "the cold start and not the road.", "",
           "The support is the crossings and instants every approach answered, "
           "chosen once over the whole recording and then cut by day, so the "
           "columns are comparable to each other.", "",
           "| approach | " + " | ".join(days) + " |",
           "|---" * (len(days) + 1) + "|"]
    counts = [max(r["n"] for r in d["days"][day].values()) for day in days]
    out.append("| _predictions_ | " + " | ".join(str(c) for c in counts) + " |")
    for n in names:
        cells = [f"{d['days'][day][n]['mae']:.0f}" if n in d["days"][day] else "-"
                 for day in days]
        out.append(f"| {n} | " + " | ".join(cells) + " |")
    out += ["", "MAE in seconds. `crossday.json` holds the 95% intervals, which "
            "are resampled over whole trips within each day and are wide enough "
            "that a gap of a second or two between two approaches on one day is "
            "not a fact about them.", ""]
    return "\n".join(out)
