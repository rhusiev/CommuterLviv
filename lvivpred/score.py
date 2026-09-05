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

Confidence intervals resample whole trips rather than single predictions. A
vehicle running late is late at every stop still ahead of it, so its errors
are one fact repeated, not thirty independent ones; resampling predictions
would report an interval several times narrower than the truth.
"""
import numpy as np

BUCKETS = [(0, 60), (60, 120), (120, 300), (300, 600), (600, 1200), (1200, 2700)]
EPOCH = 60.0


def _keys(s):
    """One integer naming (crossing, instant), so predictors can be intersected."""
    return s.event * 100000000 + (s.epoch / EPOCH).astype(np.int64)


def common(named):
    """Restrict every predictor to the events and instants all of them answered."""
    keys = {n: _keys(s) for n, s in named.items()}
    shared = None
    for k in keys.values():
        shared = k if shared is None else np.intersect1d(shared, k)
    return {n: s.select(np.isin(keys[n], shared)) for n, s in named.items()}


def coverage(named, truth):
    print(f"{'name':<10} {'crossings':>10} {'of truth':>9} {'predictions':>12}")
    for n, s in named.items():
        k = len(np.unique(s.event))
        print(f"{n:<10} {k:>10} {100 * k / max(truth.n, 1):>8.1f}% {len(s):>12}")
    print()


def table(named, truth=None, ci=False):
    w = max(len(n) for n in named)
    head = (f"{'horizon':>12}  {'name':<{w}}  {'n':>7} {'MAE':>7} {'med':>7} "
            f"{'RMSE':>7} {'bias':>7} {'<60s':>6} {'<120s':>6}")
    print(head + (f"  {'95% CI on MAE':>17}" if ci else ""))
    for lo, hi in BUCKETS:
        for name, s in named.items():
            m = (s.horizon >= lo) & (s.horizon < hi)
            n = int(m.sum())
            if not n:
                continue
            v = s.error[m]
            line = (f"{lo // 60:>4}-{hi // 60:<3} min  {name:<{w}}  {n:>7} "
                    f"{np.abs(v).mean():>7.0f} {np.median(np.abs(v)):>7.0f} "
                    f"{np.sqrt((v ** 2).mean()):>7.0f} {v.mean():>+7.0f} "
                    f"{100 * (np.abs(v) < 60).mean():>5.1f}% "
                    f"{100 * (np.abs(v) < 120).mean():>5.1f}%")
            if ci:
                a, b = bootstrap(np.abs(v), truth.trip[s.event[m]])
                line += f"  {a:>7.0f} .. {b:<7.0f}"
            print(line)
        print()


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
    print("all predictors on the crossings and instants every one of them answered\n")
    table(common(named), truth, ci=True)
