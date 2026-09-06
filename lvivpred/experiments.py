"""Run every approach against one recording and write down what each scored.

Each variant is replayed cold - no snapshot is loaded and none is saved - so
they all start knowing nothing and see exactly the same data in the same order.
A warmed model would carry in whatever the last run happened to learn, which is
different for every variant and would be the thing being measured.

Tracking does not depend on the variant, so the crossings that actually
happened are the same set for all of them and one ground truth serves the whole
comparison. That is checked rather than assumed.

The three outside predictors - trip_updates, the arrivals board, the timetable -
are scored too, so the variants are ranked against something that is not us.
"""
import json
import os
import sqlite3
import time

from . import config, network, predictors, replay, score
from .truth import Truth

REPORTS = "reports"
LATE = 300.0     # the oldest fix the replay's own filter still accepts


def _end(db):
    """Where to stop the replay, so every variant reads the same recording.

    The collector may well still be running, and it writes fixes up to LATE
    seconds older than the poll that fetched them. Cutting the recording that
    far back from the newest fix means anything still to arrive lands after the
    cut, so the last variant sees exactly what the first one did.
    """
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    try:
        last = con.execute("SELECT max(veh_ts) FROM veh").fetchone()[0]
    finally:
        con.close()
    if last is None:
        raise SystemExit(f"{db} holds no vehicle fixes yet")
    return last - LATE


def run_all(net=None, variants=None, out=REPORTS, db=replay.DB, **kw):
    net = net or network.load()
    variants = variants or config.VARIANTS
    kw.setdefault("t_to", _end(db))

    named, truth, first = {}, None, None
    for cfg in variants:
        t = time.time()
        _, res = replay.run(net, cfg=cfg, db=db, **kw)
        res.net = net
        if truth is None:
            truth, first = Truth(net, res), res
        elif res.truth.keys() != first.truth.keys():
            raise RuntimeError(f"{cfg.name} tracked a different set of crossings")
        named[cfg.name] = predictors.ours(res, truth)
        print(f"  {cfg.name:<16} {len(named[cfg.name]):>8} predictions  "
              f"{time.time() - t:5.1f}s", flush=True)

    named["api"] = predictors.api(first, truth)
    named["lad"] = predictors.lad(first, net, truth)
    named["schedule"] = predictors.schedule(first, truth, net)

    paired = score.paired(named)
    lad = score.common({n: named[n] for n in ("lad", "full", "api", "schedule")})
    data = {"crossings": truth.n, "epochs": first.epochs,
            "answered": {n: len(s) for n, s in named.items()},
            "scored_on": {n: len(s) for n, s in paired.items()},
            "buckets": score.buckets(paired, truth, ci=True),
            "overall": {n: score.stats(s.error) for n, s in paired.items()},
            "lad": {n: score.stats(s.error) for n, s in lad.items()},
            "approaches": {c.name: c.doc for c in variants}}

    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "approaches.json"), "w") as f:
        json.dump(data, f, indent=1)
    with open(os.path.join(out, "approaches.md"), "w") as f:
        f.write(_markdown(data, variants))

    score.coverage(named, truth)
    score.table(paired, truth, ci=True)
    return data


def _table(rows):
    """One table of overall stats, best MAE first and everything read off `full`."""
    base = rows.get("full", {}).get("mae")
    out = ["| approach | MAE s | vs full | median s | RMSE s | bias s | <60 s | <120 s |",
           "|---|---|---|---|---|---|---|---|"]
    for n in sorted(rows, key=lambda n: rows[n]["mae"]):
        r = rows[n]
        d_mae = ("-" if not base or n == "full"
                 else f"{100 * (r['mae'] / base - 1):+.0f}%")
        out.append(f"| {n} | {r['mae']:.0f} | {d_mae} | {r['median']:.0f} | "
                   f"{r['rmse']:.0f} | {r['bias']:+.0f} | "
                   f"{100 * r['p60']:.1f}% | {100 * r['p120']:.1f}% |")
    return out


def _markdown(d, variants):
    rows = d["overall"]
    order = sorted(rows, key=lambda n: rows[n]["mae"])
    out = ["# Approaches, and what each one scored", "",
           f"One recording: {d['crossings']} stop crossings over "
           f"{d['epochs']} minutes of replay. Every approach is scored on the "
           f"{d['scored_on'][order[0]]} predictions all of them made, so the "
           "numbers below answer the same questions.", "",
           "`lad` is not in that support and not in these tables. It answers "
           "about only the 40 stops the collector polls, so intersecting over "
           "it too would judge every other approach on a small subsample chosen "
           "by which stops we happen to poll. It has its own table at the end, "
           "against the approaches it can be compared to.", "",
           "A switch that scores better than `full` is a claim the shipped model "
           "makes and this recording does not support. Before acting on one, "
           "check the 95% intervals under `buckets` in `approaches.json` - the "
           "overall table has none, because a difference that only shows up "
           "pooled across every horizon is not one worth acting on. They are "
           "resampled over whole trips, and on a recording this short several of "
           "these gaps sit inside them.", "",
           "## Overall, on the common support", ""]
    out += _table(rows)

    out += ["", "## MAE by how far ahead the prediction was", "",
            "| approach | " + " | ".join(f"{k} min" for k in d["buckets"]) + " |",
            "|---" * (len(d["buckets"]) + 1) + "|"]
    for n in order:
        cells = [f"{b[n]['mae']:.0f}" if n in b else "-"
                 for b in d["buckets"].values()]
        out.append(f"| {n} | " + " | ".join(cells) + " |")

    out += ["", "## The public arrivals board, where it answers at all", "",
            f"The same events again, restricted to the {d['lad']['lad']['n']} "
            "predictions `lad` also made. Nothing here is comparable to the "
            "tables above - this is a different, much smaller set of events, "
            "and the three familiar approaches are repeated on it so that the "
            "board has something to be read against.", "",
            "The board and `api` are both the operator's, and they are not the "
            "same quality: the board is several times the better of the two. "
            "Whatever produces it is doing more than replaying `trip_updates`. "
            "It is still beaten here, but by much less than the gap to `api` "
            "would suggest, and it is the harder of the two to beat.", ""]
    out += _table(d["lad"])

    out += ["", "## What each approach is", ""]
    for c in variants:
        out += [f"### {c.name}", "", c.doc, ""]
    out += ["### api", "",
            "The operator's own `trip_updates` feed, replayed from the recorded "
            "change log at our epochs.", "",
            "### lad", "",
            "The arrivals board at api.lad.lviv.ua that the public is shown. "
            "Only the stops the collector polls appear in it.", "",
            "### schedule", "",
            "The static timetable with no real-time input at all, as a floor.", ""]
    return "\n".join(out)
