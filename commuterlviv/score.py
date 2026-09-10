"""Comparing predictors fairly, which is harder than it sounds.

The predictors do not answer the same questions. Over one hour ours answered
about three quarters of the crossings and trip_updates about nine tenths, and
the quarter we skip is not a random quarter - it is the vehicles we could not
track, which are the hard ones. Averaging each predictor over its own set
therefore compares different exam papers and flatters whoever attempted the
easier one.

So two numbers are reported instead of one. Coverage says how many questions
each predictor attempted at all; a predictor that answers nothing has a
wonderful error rate. The paired table then scores every predictor on only the
crossings and instants that all of them answered, which is the one comparison
where the numbers mean the same thing.

Who is in that intersection is itself a decision. A predictor that answers about
a small corner of the network drags everyone down into that corner, so the
narrow ones are held out of it and scored on a support of their own.

Confidence intervals resample whole trips rather than single predictions. A
vehicle running late is late at every stop still ahead of it, so its errors
are one fact repeated, not thirty independent ones; resampling predictions
would report an interval several times narrower than the truth.
"""
import time

import numpy as np

BUCKETS = [(0, 60), (60, 120), (120, 300), (300, 600), (600, 1200), (1200, 2700)]
EPOCH = 60.0
NARROW = ("lad",)   # predictors too narrow to set the support; see paired()
HOUR_MIN = 300      # paired predictions an hour needs before its MAE is printed
# The service day rolls here, not at midnight: the last trams run past 00:00 and
# nothing at all runs until 05:30, so a crossing at 00:20 belongs to the day that
# is ending rather than to the one that has not started.
DAY_ROLL = 3 * 3600


def keys(s):
    """One integer naming (crossing, instant), so predictors can be intersected."""
    return s.event * 100000000 + (s.epoch / EPOCH).astype(np.int64)


def bucket_of(horizon):
    """Which BUCKETS index each horizon falls in, as an array."""
    edges = np.array([hi for _, hi in BUCKETS[:-1]], dtype=float)
    return np.searchsorted(edges, horizon, "right")


def clock(epoch):
    """Local hour of day and local service date for each prediction.

    Epochs are a minute apart, so a recording holds a few thousand distinct ones
    however many predictions it carries: the calendar conversion is done on the
    distinct values and mapped back, not a million times over.
    """
    u, inv = np.unique(epoch, return_inverse=True)
    tm = [time.localtime(t) for t in u]
    hour = np.array([x.tm_hour for x in tm])[inv]
    day = np.array([time.strftime("%Y-%m-%d", time.localtime(t - DAY_ROLL))
                    for t in u])[inv]
    return hour, day


def common(named):
    """Restrict every predictor to the events and instants all of them answered.

    Which predictors go in decides what every one of them is judged on, so a
    predictor that answers about few stops belongs in a call of its own rather
    than in the one the main comparison uses.
    """
    by_name = {n: keys(s) for n, s in named.items()}
    shared = None
    for k in by_name.values():
        shared = k if shared is None else np.intersect1d(shared, k)
    return {n: s.select(np.isin(by_name[n], shared)) for n, s in named.items()}


def paired(named):
    """The main comparison's support: everyone but the narrow predictors.

    The arrivals board answers about only the 40 stops the collector polls, so
    intersecting over it too would judge every other approach on a subsample
    chosen by which stops we happen to poll. It is scored on its own support.
    """
    return common({n: s for n, s in named.items() if n not in NARROW})


def coverage(named, truth):
    print(f"{'name':<10} {'crossings':>10} {'of truth':>9} {'predictions':>12}")
    for n, s in named.items():
        k = len(np.unique(s.event))
        print(f"{n:<10} {k:>10} {100 * k / max(truth.n, 1):>8.1f}% {len(s):>12}")
    print()


def stats(v):
    """The one summary of a set of errors, so printing and saving agree."""
    a = np.abs(v)
    return {"n": int(len(v)), "mae": float(a.mean()),
            "median": float(np.median(a)), "rmse": float(np.sqrt((v ** 2).mean())),
            "bias": float(v.mean()), "p60": float((a < 60).mean()),
            "p120": float((a < 120).mean())}


def buckets(named, truth=None, ci=False):
    """Every predictor's stats in every horizon bucket, as plain data."""
    out = {}
    for lo, hi in BUCKETS:
        for name, s in named.items():
            m = (s.horizon >= lo) & (s.horizon < hi)
            if not m.any():
                continue
            row = stats(s.error[m])
            if ci:
                a, b = bootstrap(np.abs(s.error[m]), truth.trip[s.event[m]])
                row["ci"] = [float(a), float(b)]
            out.setdefault(f"{lo // 60}-{hi // 60}", {})[name] = row
    return out


def table(named, truth=None, ci=False):
    w = max(len(n) for n in named)
    head = (f"{'horizon':>12}  {'name':<{w}}  {'n':>7} {'MAE':>7} {'med':>7} "
            f"{'RMSE':>7} {'bias':>7} {'<60s':>6} {'<120s':>6}")
    print(head + (f"  {'95% CI on MAE':>17}" if ci else ""))
    for label, rows in buckets(named, truth, ci).items():
        lo, hi = label.split("-")
        for name, r in rows.items():
            line = (f"{lo:>4}-{hi:<3} min  {name:<{w}}  {r['n']:>7} "
                    f"{r['mae']:>7.0f} {r['median']:>7.0f} {r['rmse']:>7.0f} "
                    f"{r['bias']:>+7.0f} {100 * r['p60']:>5.1f}% "
                    f"{100 * r['p120']:>5.1f}%")
            if ci:
                line += f"  {r['ci'][0]:>7.0f} .. {r['ci'][1]:<7.0f}"
            print(line)
        print()


def hours(named, min_n=HOUR_MIN):
    """MAE by local hour of day, with counts.

    An hour with fewer than `min_n` predictions is left out rather than printed:
    a recording that clips the end of an evening carries a handful of rows at
    23:00, and an MAE over a handful of rows is a number nobody should read.
    """
    out = {}
    for name, s in named.items():
        hour, _ = clock(s.epoch)
        for h in np.unique(hour):
            m = hour == h
            if m.sum() >= min_n:
                out.setdefault(f"{h:02d}", {})[name] = stats(s.error[m])
    return dict(sorted(out.items()))


def hour_table(named, min_n=HOUR_MIN):
    rows = hours(named, min_n)
    w = max(len(n) for n in named)
    print(f"{'hour':>6}  {'name':<{w}}  {'n':>8} {'MAE':>7} {'med':>7} {'bias':>7}")
    for label, per in rows.items():
        for name, r in per.items():
            print(f"{label + ':00':>6}  {name:<{w}}  {r['n']:>8} "
                  f"{r['mae']:>7.0f} {r['median']:>7.0f} {r['bias']:>+7.0f}")
        print()
    return rows


def bootstrap(vals, trips, n=500, seed=0, chunk=50):
    """Percentile interval for a mean, resampling whole trips."""
    rng = np.random.default_rng(seed)
    u, inv = np.unique(trips, return_inverse=True)
    out = []
    for i in range(0, n, chunk):
        k = min(chunk, n - i)
        w = rng.multinomial(len(u), np.full(len(u), 1 / len(u)), size=k)[:, inv]
        out.append((w * vals).sum(1) / np.maximum(w.sum(1), 1))
    return np.percentile(np.concatenate(out), [2.5, 97.5])


def report(named, truth):
    coverage(named, truth)
    print("each predictor on everything it answered\n")
    table(named)
    common_support = paired(named)
    print(f"all predictors but {', '.join(NARROW)} on the crossings and "
          "instants every one of them answered\n")
    table(common_support, truth, ci=True)
    print("the same predictions, by the hour of day they were made\n")
    hour_table(common_support)
