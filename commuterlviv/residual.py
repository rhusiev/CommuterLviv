"""Phase 4: an offline model of what the shipped model gets wrong.

The target is not the arrival time. Predicting that from scratch throws away a
physical model that is already within two minutes; what is left to learn is the
*ratio* between what really happened and what that model said, in log space, so
a correction multiplies an ETA instead of adding seconds to it. Thirty seconds
of optimism at forty minutes and at one minute are not the same mistake.

Causality is the whole constraint and it is enforced twice. Every column in
`features.py` was readable at the instant the prediction was made, and the split
here is by that instant: fit on rows emitted before midnight, score on rows
emitted from 05:30 on. One replay produces both, so the physical model's state
at 05:30 carries the evening's learning exactly as it would in deployment, and
the residual model still never sees a row from its own test window.

Five models, in increasing order of what they can express, each scored against
the uncorrected model and against the one before it, so the table says what the
extra capacity bought. Then the same residual at its 10th and 90th percentile,
which is an interval on the arrival time rather than a point - the one output
here that says "6 to 11 minutes" - graded by coverage, width and pinball loss
because MAE cannot grade an interval:

    python3 -m commuterlviv residual --feats reports/feats.npz
"""
import dataclasses
import json
import os
import time

import numpy as np

from . import features, score

FIT_TO = "2026-09-06T00:00"
TEST_FROM = "2026-09-06T05:30"
COLD = 2400.0          # the model's first 40 minutes, still learning the road
REPORTS = os.path.join(os.path.dirname(os.path.dirname(__file__)), "reports")
CLIP = features.TARGET_CLIP
MIN_ROUTE = 500        # rows a route needs before it gets a column of its own


def split(rows, fit_to, test_from, cold=COLD):
    """Train and test rows, by the time each prediction was emitted.

    The gap between them is not slack: it is the hours the recording spends
    with no service, so nothing falls in it anyway.
    """
    t0 = rows.at.min()
    train = rows.select((rows.at >= t0 + cold) & (rows.at < fit_to))
    test = rows.select(rows.at >= test_from)
    if not len(train) or not len(test):
        raise SystemExit(f"{len(train)} training rows and {len(test)} test rows; "
                         "the recording does not span the split")
    return train, test


class Const:
    """One number per horizon bucket: the mean residual there.

    A sanity floor - if this beats the shipped model, the model has a bias. It
    is fitted per bucket rather than pooled because pooled it would find almost
    nothing: the model runs late at one minute and early at forty, and those two
    biases cancel.
    """

    name = "resid-const"

    def fit(self, rows):
        b = score.bucket_of(rows.eta)
        self.by_bucket = np.zeros(len(score.BUCKETS))
        for i in range(len(self.by_bucket)):
            m = b == i
            if m.any():
                self.by_bucket[i] = np.average(rows.y[m], weights=rows.w[m])
        return self

    def correct(self, rows):
        return self.by_bucket[score.bucket_of(rows.eta)]


class BucketQuantile:
    """One number per horizon bucket: the q-th percentile of the residual there.

    The fit-free floor an interval has to beat. It knows only that a prediction
    forty minutes out is uncertain in a way a one-minute one is not, which is
    most of what an interval is for - so if the trees cannot beat this, the
    interval does not need a model.
    """

    def __init__(self, q):
        self.q = q
        self.name = f"band-const-{q:g}"

    def fit(self, rows):
        b = score.bucket_of(rows.eta)
        self.by_bucket = np.zeros(len(score.BUCKETS))
        for i in range(len(self.by_bucket)):
            m = b == i
            if m.any():
                self.by_bucket[i] = _wquantile(rows.y[m], rows.w[m], self.q)
        return self

    def correct(self, rows):
        return self.by_bucket[score.bucket_of(rows.eta)]


def _wquantile(v, w, q):
    """Weighted quantile, by the same weights the point models are fitted with."""
    o = np.argsort(v)
    v, w = v[o], w[o]
    c = np.cumsum(w) - 0.5 * w
    return float(np.interp(q * w.sum(), c, v))


class Ridge:
    """Weighted least squares on the features, with the penalty chosen on a
    held-out tail of the training window.

    The design matrix is never materialised: at two million rows it would be
    gigabytes, while the normal equations it feeds are a few hundred squared.
    So one pass accumulates them in chunks, and every penalty is then solved
    from the same accumulation.
    """

    name = "resid-linear"
    LAMBDAS = (1e-4, 1e-3, 1e-2, 1e-1, 1.0, 10.0, 100.0)

    def fit(self, rows, val_frac=0.2):
        self.design = Design(rows)
        cut = np.quantile(rows.at, 1 - val_frac)
        inner, val = rows.select(rows.at < cut), rows.select(rows.at >= cut)
        a, b = self.design.normal(inner)
        best = min(self.LAMBDAS,
                   key=lambda lam: _mae(val, self._solve(a, b, lam), self.design))
        self.lam = best
        a, b = self.design.normal(rows)
        self.beta = self._solve(a, b, best)
        return self

    def _solve(self, a, b, lam):
        p = np.eye(len(a)) * lam * len(a)
        p[-1, -1] = 0.0                       # never penalise the intercept
        return np.linalg.solve(a + p, b)

    def correct(self, rows):
        return self.design.apply(rows, self.beta)


class Design:
    """The features a linear model sees: standardised, with a few log scales.

    `eta` and `dist` span three decades, so a linear coefficient on either is
    dominated by the far end of the horizon; their logs are the scale on which
    the correction is plausibly linear. The hour of day becomes a sine and a
    cosine so that 23:50 and 00:10 are neighbours. The route is a name, not a
    number, so it becomes one column per route with enough rows to fit one.
    """

    LOG = ("eta", "dist", "headway")
    DROP = ("route", "hour")

    def __init__(self, rows):
        self.cols = [c for c in rows.cols if c not in self.DROP]
        self.routes = _common(rows.col("route"), MIN_ROUTE)
        z = self._raw(rows.select(slice(None, None, max(1, len(rows) // 200000))))
        self.mu, self.sd = z.mean(0), np.maximum(z.std(0), 1e-6)
        self.names = (self.cols + ["hour_sin", "hour_cos"]
                      + [f"route_{int(r)}" for r in self.routes] + ["1"])

    def _raw(self, rows):
        z = [np.log(np.maximum(rows.col(c), 1.0)) if c in self.LOG
             else rows.col(c) for c in self.cols]
        h = rows.col("hour") * (2 * np.pi / 24.0)
        z += [np.sin(h), np.cos(h)]
        r = rows.col("route")
        z += [(r == v).astype(float) for v in self.routes]
        return np.stack(z, axis=1)

    def matrix(self, rows):
        z = (self._raw(rows) - self.mu) / self.sd
        return np.concatenate([z, np.ones((len(z), 1))], axis=1)

    def normal(self, rows, chunk=200000):
        p = len(self.names)
        a, b = np.zeros((p, p)), np.zeros(p)
        for lo in range(0, len(rows), chunk):
            part = rows.select(slice(lo, lo + chunk))
            z = self.matrix(part)
            zw = z * part.w[:, None]
            a += z.T @ zw
            b += zw.T @ part.y
        return a / len(rows), b / len(rows)

    def apply(self, rows, beta, chunk=200000):
        out = np.empty(len(rows))
        for lo in range(0, len(rows), chunk):
            part = rows.select(slice(lo, lo + chunk))
            out[lo:lo + len(part)] = self.matrix(part) @ beta
        return out


class Gbm:
    """Gradient-boosted trees, which is what "ML" means in this comparison.

    `scikit-learn` is an optional extra here and deliberately not in
    `requirements.txt`: the collector runs on a small VPS and this never runs
    there. Early stopping is on a slice held out of the *training* window, so
    no test row is consulted even to decide when to stop.
    """

    def __init__(self, name="resid-gbm", quantile=None, val_frac=0.15, **kw):
        self.name = name
        self.quantile = quantile
        self.val_frac = val_frac
        self.kw = kw

    def fit(self, rows):
        from sklearn.ensemble import HistGradientBoostingRegressor

        loss = "squared_error" if self.quantile is None else "quantile"
        extra = {} if self.quantile is None else {"quantile": self.quantile}
        cat = np.array([c == "route" for c in rows.cols])
        if len(np.unique(rows.col("route"))) > 200:
            cat[:] = False
        self.m = HistGradientBoostingRegressor(
            loss=loss, categorical_features=cat, early_stopping=True,
            validation_fraction=self.val_frac, random_state=0, **extra, **self.kw)
        self.m.fit(rows.x, rows.y, sample_weight=rows.w)
        return self

    def correct(self, rows):
        return np.clip(self.m.predict(rows.x), -CLIP, CLIP)


class Mlp:
    """Two hidden layers, in numpy, on a subsample.

    Expected to lose: a few hundred effective facts cannot fit a few thousand
    parameters, and this recording has far fewer independent facts than rows.
    It is here so the report can say by how much instead of asserting it.
    """

    name = "resid-mlp"

    def __init__(self, hidden=(48, 32), epochs=12, batch=1024, lr=3e-3,
                 cap=300000, seed=0):
        self.hidden, self.epochs, self.batch = hidden, epochs, batch
        self.lr, self.cap, self.seed = lr, cap, seed

    def fit(self, rows):
        rng = np.random.default_rng(self.seed)
        if len(rows) > self.cap:
            rows = rows.select(rng.choice(len(rows), self.cap, replace=False))
        self.design = Design(rows)
        z, y, w = self.design.matrix(rows), rows.y, rows.w
        sizes = [z.shape[1], *self.hidden, 1]
        self.wb = [(rng.normal(0, np.sqrt(2 / a), (a, b)), np.zeros(b))
                   for a, b in zip(sizes, sizes[1:])]
        adam = [(np.zeros_like(m), np.zeros_like(m)) for p in self.wb for m in p]
        step = 0
        for _ in range(self.epochs):
            for i in _batches(rng, len(z), self.batch):
                step += 1
                self._step(z[i], y[i], w[i], adam, step)
        return self

    def _forward(self, z):
        acts = [z]
        for k, (w, b) in enumerate(self.wb):
            h = acts[-1] @ w + b
            acts.append(h if k == len(self.wb) - 1 else np.maximum(h, 0.0))
        return acts

    def _step(self, z, y, w, adam, step, beta=(0.9, 0.999), eps=1e-8):
        acts = self._forward(z)
        g = (2.0 * w[:, None] * (acts[-1] - y[:, None])) / len(z)
        for k in range(len(self.wb) - 1, -1, -1):
            grads = (acts[k].T @ g, g.sum(0))
            if k:
                g = (g @ self.wb[k][0].T) * (acts[k] > 0)
            for j, grad in enumerate(grads):
                m, v = adam[2 * k + j]
                m *= beta[0]; m += (1 - beta[0]) * grad
                v *= beta[1]; v += (1 - beta[1]) * grad ** 2
                mh = m / (1 - beta[0] ** step)
                vh = v / (1 - beta[1] ** step)
                self.wb[k][j][...] -= self.lr * mh / (np.sqrt(vh) + eps)

    def correct(self, rows, chunk=200000):
        out = np.empty(len(rows))
        for lo in range(0, len(rows), chunk):
            part = rows.select(slice(lo, lo + chunk))
            z = self.design.matrix(part)
            out[lo:lo + len(part)] = self._forward(z)[-1][:, 0]
        return np.clip(out, -CLIP, CLIP)


def _batches(rng, n, size):
    order = rng.permutation(n)
    for lo in range(0, n - size + 1, size):
        yield order[lo:lo + size]


def _common(v, floor):
    u, n = np.unique(v, return_counts=True)
    return u[n >= floor]


def _mae(rows, beta_or_corr, design=None):
    corr = design.apply(rows, beta_or_corr) if design is not None else beta_or_corr
    return float(np.abs(rows.error(np.clip(corr, -CLIP, CLIP))).mean())


def evaluate(train, test, models):
    """Fit each model on the training rows and score it in seconds on the test.

    Scored the way every other approach in this project is scored - absolute
    error against the crossing that really happened, bucketed by how far ahead
    the prediction was, with an interval resampled over whole trips. The
    interval is on the *difference* from the uncorrected model, because the two
    answer identical rows and a paired interval is the only one narrow enough
    to say anything on a recording this short.
    """
    base = np.abs(test.error())
    out = {"full": {"overall": score.stats(test.error()),
                    "buckets": _by_bucket(test, test.error()), "fit_s": 0.0}}
    for m in models:
        t0 = time.time()
        m.fit(train)
        corr = np.clip(m.correct(test), -CLIP, CLIP)
        err = test.error(corr)
        lo, hi = score.bootstrap(np.abs(err) - base, test.trip)
        out[m.name] = {"overall": score.stats(err), "buckets": _by_bucket(test, err),
                       "delta": float(np.abs(err).mean() - base.mean()),
                       "ci": [float(lo), float(hi)], "fit_s": time.time() - t0}
        print(f"{m.name:<14} MAE {out[m.name]['overall']['mae']:>6.1f} s "
              f"({out[m.name]['delta']:+.1f} [{lo:+.1f}, {hi:+.1f}]) "
              f"in {out[m.name]['fit_s']:.0f} s")
    return out


def _by_bucket(rows, err):
    h = rows.t - rows.at
    out = {}
    for lo, hi in score.BUCKETS:
        m = (h >= lo) & (h < hi)
        if m.any():
            out[f"{lo // 60}-{hi // 60}"] = score.stats(err[m])
    return out


BAND = (0.1, 0.9)


def intervals(train, test, makers, band=BAND):
    """Fit a low and a high quantile of the same residual, and grade the band.

    A quantile of the log ratio is a quantile of the arrival time, because the
    map from one to the other is increasing: multiplying the ETA by `exp` of the
    10th percentile correction gives the 10th percentile arrival. So the pair of
    corrections is an interval in seconds, and it is graded as an interval -
    MAE grades a point and says nothing here.

    Three numbers, because no one of them can be read alone. Coverage is what
    fraction of predictions fell inside the band, and 80% is the target; width is
    what the band costs to say, since an infinitely wide one covers everything;
    pinball loss is the proper score that trades the two, and is the only one of
    the three a model can be ranked by.
    """
    out = {}
    for name, make in makers.items():
        t0 = time.time()
        edges = [np.clip(make(q).fit(train).correct(test), -CLIP, CLIP)
                 for q in band]
        out[name] = _grade(test, edges, band) | {"fit_s": time.time() - t0}
        r = out[name]
        print(f"{name:<14} covers {100 * r['coverage']:>5.1f}% of predictions, "
              f"width {r['width']:>5.0f} s, pinball "
              + " / ".join(f"{p:.1f}" for p in r["pinball"])
              + f" s in {r['fit_s']:.0f} s")
    return out


def _grade(test, edges, band):
    """Coverage, width and pinball loss, all in seconds against the truth.

    `rows.error` is the predicted arrival minus the real one, so the truth sits
    at zero and the band covers it when the low edge is early and the high edge
    late. Quantile models are fitted independently and can cross; the edges are
    sorted so the band is always a band, and how often that had to happen is
    reported rather than hidden.
    """
    err = [test.error(e) for e in edges]
    lo, hi = np.minimum(*err), np.maximum(*err)
    width = hi - lo
    return {"coverage": float(((lo <= 0) & (hi >= 0)).mean()),
            "target": band[1] - band[0],
            "width": float(width.mean()), "width_median": float(np.median(width)),
            "pinball": [_pinball(e, q) for e, q in zip(err, band)],
            "crossed": float((err[0] > err[1]).mean()),
            "buckets": _band_buckets(test, lo, hi)}


def _pinball(err, q):
    """The check loss, on seconds late (negative early) rather than on a level."""
    u = -err
    return float(np.maximum(q * u, (q - 1.0) * u).mean())


def _band_buckets(rows, lo, hi):
    h = rows.t - rows.at
    out = {}
    for a, b in score.BUCKETS:
        m = (h >= a) & (h < b)
        if m.any():
            out[f"{a // 60}-{b // 60}"] = {
                "coverage": float(((lo[m] <= 0) & (hi[m] >= 0)).mean()),
                "width": float((hi[m] - lo[m]).mean()), "n": int(m.sum())}
    return out


def bands(quick=False):
    out = {"band-const": BucketQuantile}
    if not quick and _has_sklearn():
        out["band-quantile"] = lambda q: Gbm(f"band-{q:g}", quantile=q,
                                             max_depth=6, learning_rate=0.1,
                                             max_iter=400)
    return out


def ablate(train, test, model_of, groups):
    """Refit the winner with one feature group blanked out at a time.

    Blanked rather than removed, so every fit sees the same matrix shape and
    the same hyperparameters, and the only thing that changes is whether the
    column carries information. The blanking is only ever what the model is
    shown: the error is always measured against the untouched rows, since one
    of the blanked columns is the ETA being corrected.
    """
    base = None
    out = {}
    for name, cols in [("none", ())] + list(groups.items()):
        m = model_of().fit(_blank(train, cols))
        corr = np.clip(m.correct(_blank(test, cols)), -CLIP, CLIP)
        mae = float(np.abs(test.error(corr)).mean())
        base = mae if base is None else base
        out[name] = {"mae": mae, "cost": mae - base}
        print(f"  without {name:<12} MAE {mae:>6.1f} s ({mae - base:+.1f})")
    return out


def _blank(rows, cols):
    if not cols:
        return rows
    x = rows.x.copy()
    for c in cols:
        x[:, rows.cols.index(c)] = 0.0
    return dataclasses.replace(rows, x=x)


ABLATION = {
    "horizon": ("eta", "dist", "n_stops"),
    "evidence": ("w_cell_fast", "w_cell_slow", "w_corr_fast"),
    "vehicle": ("factor", "factor_age", "fix_age"),
    "timetable": ("sched", "late", "headway"),
    "context": ("hour", "route"),
}


def models(quick=False):
    out = [Const(), Ridge()]
    if _has_sklearn():
        out.append(Gbm(max_depth=6, learning_rate=0.1, max_iter=400))
        out.append(Gbm("resid-quantile", quantile=0.5, max_depth=6,
                       learning_rate=0.1, max_iter=400))
    if not quick:
        out.append(Mlp())
    return out


def _has_sklearn():
    try:
        import sklearn                                          # noqa: F401
    except ImportError:
        print("scikit-learn is not installed; skipping the tree models")
        return False
    return True


def main(feats="reports/feats.npz", fit_to=None, test_from=None, quick=False,
         out=REPORTS, ablation=True, label=""):
    rows = features.load(feats)
    train, test = split(rows, fit_to or _when(FIT_TO), test_from or _when(TEST_FROM))
    print(f"{len(train)} training rows, {len(test)} test rows, "
          f"{len(np.unique(test.event))} test crossings\n")
    res = evaluate(train, test, models(quick))
    print(f"\n{100 * (BAND[1] - BAND[0]):.0f}% prediction interval")
    band = intervals(train, test, bands(quick))
    abl = {}
    if ablation and not quick:
        best = min((n for n in res if n != "full"),
                   key=lambda n: res[n]["overall"]["mae"])
        print(f"\nfeature ablation on {best}")
        abl = {best: ablate(train, test, _model_of(best), ABLATION)}
    report(res, abl, band, train, test, out, label)
    return res


def _model_of(name):
    return lambda: next(m for m in models() if m.name == name)


def _when(s):
    import datetime
    return datetime.datetime.fromisoformat(s).timestamp()


def _stamp(t):
    import datetime
    from .model import TZ
    return datetime.datetime.fromtimestamp(t, TZ).strftime("%m-%d %H:%M")


def _cell(row):
    return "-" if row is None else f"{row['mae']:.0f}"


def report(res, abl, band, train, test, out, label=""):
    os.makedirs(out, exist_ok=True)
    stem = "residual" + (f"-{label}" if label else "")
    payload = {"train_rows": len(train), "test_rows": len(test),
               "test_crossings": int(len(np.unique(test.event))),
               "split": [float(train.at.max()), float(test.at.min())],
               "models": res, "ablation": abl, "interval": band}
    with open(os.path.join(out, f"{stem}.json"), "w") as f:
        json.dump(payload, f, indent=1, sort_keys=True)

    base = res["full"]["overall"]["mae"]
    lines = ["# Correcting the model's residual", "",
             f"Fitted on the {len(train)} predictions emitted from "
             f"{_stamp(train.at.min())} to {_stamp(train.at.max())}, and scored "
             f"on the {len(test)} emitted from {_stamp(test.at.min())} to "
             f"{_stamp(test.at.max())}, covering {payload['test_crossings']} "
             "crossings. Every model corrects the same physical model on the "
             "same rows, so the intervals are on the difference from it and not "
             "on either MAE.", "",
             "| model | MAE s | vs full | 95% CI on the difference | median s | "
             "bias s | <60 s |", "|---|---|---|---|---|---|---|"]
    for name, r in sorted(res.items(), key=lambda kv: kv[1]["overall"]["mae"]):
        o = r["overall"]
        ci = (f"{r['ci'][0]:+.1f} .. {r['ci'][1]:+.1f}" if "ci" in r else "-")
        lines.append(f"| {name} | {o['mae']:.1f} | "
                     f"{100 * (o['mae'] - base) / base:+.1f}% | {ci} | "
                     f"{o['median']:.0f} | {o['bias']:+.0f} | "
                     f"{100 * o['p60']:.1f}% |")
    lines += ["", "## By horizon, MAE in seconds", "",
              "| model | " + " | ".join(f"{lo // 60}-{hi // 60}"
                                        for lo, hi in score.BUCKETS) + " |",
              "|---" * (1 + len(score.BUCKETS)) + "|"]
    for name, r in sorted(res.items(), key=lambda kv: kv[1]["overall"]["mae"]):
        cells = [_cell(r["buckets"].get(f"{lo // 60}-{hi // 60}"))
                 for lo, hi in score.BUCKETS]
        lines.append(f"| {name} | " + " | ".join(cells) + " |")
    if band:
        pct = 100 * (BAND[1] - BAND[0])
        lines += ["", f"## The {pct:.0f}% prediction interval", "",
                  f"The {BAND[0]:g} and {BAND[1]:g} quantiles of the same "
                  "residual, read as an interval on the arrival time. Coverage "
                  f"should be {pct:.0f}%; width is what the band costs to say; "
                  "pinball loss is the proper score that trades the two and the "
                  "only column models can be ranked by.", "",
                  "| band | coverage | width s | median width s | "
                  f"pinball {BAND[0]:g} | pinball {BAND[1]:g} | edges crossed |",
                  "|---|---|---|---|---|---|---|"]
        for name, r in sorted(band.items(), key=lambda kv: sum(kv[1]["pinball"])):
            lines.append(f"| {name} | {100 * r['coverage']:.1f}% | "
                         f"{r['width']:.0f} | {r['width_median']:.0f} | "
                         + " | ".join(f"{p:.1f}" for p in r["pinball"])
                         + f" | {100 * r['crossed']:.1f}% |")
        lines += ["", "Coverage and mean width by horizon:", "",
                  "| band | " + " | ".join(f"{lo // 60}-{hi // 60}"
                                           for lo, hi in score.BUCKETS) + " |",
                  "|---" * (1 + len(score.BUCKETS)) + "|"]
        for name, r in sorted(band.items(), key=lambda kv: sum(kv[1]["pinball"])):
            cells = []
            for lo, hi in score.BUCKETS:
                b = r["buckets"].get(f"{lo // 60}-{hi // 60}")
                cells.append("-" if b is None
                             else f"{100 * b['coverage']:.0f}% / {b['width']:.0f} s")
            lines.append(f"| {name} | " + " | ".join(cells) + " |")
    for name, rows in abl.items():
        lines += ["", f"## What carries {name}", "",
                  "Each group of features is blanked and the model refitted; the "
                  "cost is what the correction loses without it.", "",
                  "| dropped | MAE s | cost s |", "|---|---|---|"]
        lines += [f"| {g} | {r['mae']:.1f} | {r['cost']:+.1f} |"
                  for g, r in rows.items()]
    with open(os.path.join(out, f"{stem}.md"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"\n-> {os.path.join(out, stem + '.md')}")
