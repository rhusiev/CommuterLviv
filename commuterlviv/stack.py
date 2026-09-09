"""Phase 5: blending predictors that fail differently at different horizons.

Nothing here is a new model of the road. The four things being blended are
already scored in `reports/approaches.md`, and the whole idea rests on one
measurement: they do not fail in the same place. `full` leads overall,
`no-prior` beats it in the first minutes, `sections` is a coarser model that
survives where the fine one has no evidence, and the operator's `api` has a
decent median and a terrible tail. A blend can only win if the errors are less
than perfectly correlated, so the report prints that correlation next to the
result rather than leaving it to be assumed.

Weights are fitted per horizon bucket, on predictions emitted before the split
and scored on predictions emitted after it - the same causal split as Phase 4,
for the same reason. Three blend rules are fitted, and they differ only in what
they are protecting against:

  stack         weights that minimise squared error, the textbook stack
  stack-robust  the same weights fitted to minimise absolute error instead
  stack-median  no weights at all: the member-wise median of what they said
  debias        `full` alone, with only the per-bucket intercept fitted

The third is the one that answers the plan's worry about the `api` tail. A
fitted linear blend still passes a wild value straight through, however it was
fitted; a median cannot, as long as the wild member is outnumbered.

The fourth blends nothing and exists to keep the others honest. Every blend
here carries a per-horizon intercept, and the intercepts it fits are large -
so a control that fits *only* those intercepts says how much of a stack's win
is mixing predictors and how much is just removing a bias the members share.

    python3 -m commuterlviv stack
"""
import dataclasses
import json
import os
import time

import numpy as np

from . import config, features, network, predictors, replay, residual, score

MEMBERS = ("full", "no-prior", "sections")
BASE = "full"
MIN_FIT = 500           # rows a bucket needs before its weights are fitted
HUBER = 30.0            # seconds below which the robust fit stops caring
REPORTS = residual.REPORTS


@dataclasses.dataclass
class Panel:
    """What every member said about the same crossing at the same instant.

    One row per (crossing, epoch) that all of them answered, one column of
    errors per member. Blending is then arithmetic on `err`: the members share
    a truth, so a weighted mean of their errors is the error of the weighted
    mean of their predictions, and no arrival times need carrying.
    """

    names: tuple[str, ...]
    err: np.ndarray
    event: np.ndarray
    epoch: np.ndarray
    horizon: np.ndarray
    trip: np.ndarray
    keys: np.ndarray

    def __len__(self):
        return self.err.shape[1]

    def select(self, mask):
        return dataclasses.replace(
            self, err=self.err[:, mask],
            **{f.name: getattr(self, f.name)[mask]
               for f in dataclasses.fields(self)
               if f.name not in ("names", "err")})

    def of(self, name):
        return self.err[self.names.index(name)]


def panel(named, truth):
    """Align the members on the crossings and instants all of them answered.

    Each member is reduced to one error per key first: a predictor that
    answered the same instant twice would otherwise decide, by the order its
    rows happen to be in, which of its two answers everyone is compared to.
    """
    unique, shared = {}, None
    for name, s in named.items():
        k, i = np.unique(score.keys(s), return_index=True)
        unique[name] = (k, i)
        shared = k if shared is None else np.intersect1d(shared, k)
    if not len(shared):
        raise SystemExit("the members share no crossing and instant")

    err, anchor = [], None
    for name in named:
        k, i = unique[name]
        pos = i[np.searchsorted(k, shared)]
        err.append(named[name].error[pos])
        if anchor is None:
            anchor = named[name].select(pos)
    return Panel(names=tuple(named), err=np.stack(err), event=anchor.event,
                 epoch=anchor.epoch, horizon=anchor.horizon,
                 trip=truth.trip[anchor.event], keys=shared)


def split(p, fit_to, test_from, cold=residual.COLD):
    """Train and test, by the instant each prediction was emitted.

    The first `cold` seconds are dropped from the training window for the same
    reason Phase 4 drops them: every member is still learning the road there,
    and weights fitted on a cold model would describe a state that never
    recurs after the first morning.
    """
    train = p.select((p.epoch >= p.epoch.min() + cold) & (p.epoch < fit_to))
    test = p.select(p.epoch >= test_from)
    if not len(train) or not len(test):
        raise SystemExit(f"{len(train)} training rows and {len(test)} test rows; "
                         "the recording does not span the split")
    return train, test


class Blend:
    """A weight vector per horizon bucket, and the intercept beside it.

    The weights are made to sum to one by construction rather than by penalty:
    one member is the base and the others enter as differences from it, so
    whatever the fit does the blend stays an average of predictions and not a
    scaling of them. The intercept is the one thing allowed to move the level,
    which is how a bucket with a shared bias gets it removed.
    """

    def __init__(self, name="stack", loss="l2", base=BASE, only=None):
        self.name, self.loss, self.base, self.only = name, loss, base, only

    def fit(self, p):
        self.names, self.i0 = p.names, p.names.index(self.base)
        self.used = [j for j, n in enumerate(p.names)
                     if j != self.i0 and (self.only is None or n in self.only)]
        self.w = np.zeros((len(score.BUCKETS), len(p.names)))
        self.b = np.zeros(len(score.BUCKETS))
        self.w[:, self.i0] = 1.0
        for i in range(len(score.BUCKETS)):
            part = p.select(score.bucket_of(p.horizon) == i)
            if len(part) >= MIN_FIT:
                self.w[i], self.b[i] = self._one(part)
        return self

    def _one(self, p):
        e0 = p.of(self.base)
        d = np.stack([p.err[j] - e0 for j in self.used] + [np.ones(len(p))], axis=1)
        a = self._solve(d, -e0)
        w = np.zeros(len(p.names))
        w[self.used], w[self.i0] = a[:-1], 1.0 - a[:-1].sum()
        return w, a[-1]

    def _solve(self, d, y, iters=8, ridge=1e-6):
        a = np.linalg.solve(d.T @ d + ridge * len(d) * np.eye(d.shape[1]), d.T @ y)
        if self.loss == "l2":
            return a
        for _ in range(iters):
            v = 1.0 / np.maximum(np.abs(d @ a - y), HUBER)
            dv = d * v[:, None]
            a = np.linalg.solve(dv.T @ d + ridge * len(d) * np.eye(d.shape[1]),
                                dv.T @ y)
        return a

    def error(self, p):
        i = score.bucket_of(p.horizon)
        return (self.w[i] * p.err.T).sum(1) + self.b[i]

    def table(self):
        return {f"{lo // 60}-{hi // 60}":
                {"weights": dict(zip(self.names, self.w[i].round(3).tolist())),
                 "intercept": float(self.b[i])}
                for i, (lo, hi) in enumerate(score.BUCKETS)}


class Median:
    """The member-wise median, fitted to nothing.

    It has no weights to learn, so it is the only rule here that cannot
    overfit the training window - and the only one a single absurd member
    cannot drag. With an even number of members it is the mean of the middle
    two, which is still bounded by them.
    """

    name = "stack-median"

    def fit(self, p):
        return self

    def error(self, p):
        return np.median(p.err, axis=0)

    def table(self):
        return {}


def hybrid(rows, test, fit_to, test_from, model=None):
    """`full` corrected by the Phase 4 residual model, on the panel's own rows.

    The correction is fitted on the same window the blends are and then read
    off at the panel's instants. The feature rows come from a separate replay
    of the same recording, so the join is checked rather than assumed: if the
    two runs numbered their crossings differently the overlap collapses and
    this says so instead of quietly scoring a different question.
    """
    model = model or residual.Gbm("resid-quantile", quantile=0.5, max_depth=6,
                                  learning_rate=0.1, max_iter=400)
    fit, _ = residual.split(rows, fit_to, test_from)
    model.fit(fit)

    keys = rows.event * 100000000 + (rows.at / score.EPOCH).astype(np.int64)
    order = np.argsort(keys)
    pos = order[np.minimum(np.searchsorted(keys[order], test.keys), len(rows) - 1)]
    found = keys[pos] == test.keys
    if found.mean() < 0.9:
        raise SystemExit(
            f"only {100 * found.mean():.1f}% of the test panel is in the feature "
            "table; it was dumped from a different replay window")

    part = rows.select(pos[found])
    err = test.of(BASE).copy()
    err[found] = part.error(np.clip(model.correct(part),
                                    -residual.CLIP, residual.CLIP))
    return model.name, err


def series(net=None, db=replay.DB, members=MEMBERS, **kw):
    """Replay the member variants and add the operator's feed to them."""
    net = net or network.load()
    named, truth, rec = replay.run_many(
        net, [config.BY_NAME[n] for n in members], db=db, **kw)
    named["api"] = predictors.api(rec, truth)
    return named, truth


def evaluate(train, test, rules, extra=None):
    """Fit each rule on the training panel and score it on the test panel.

    Scored against `full` and only against `full`: the interval is a paired
    bootstrap of the difference over whole trips, because every rule answers
    exactly the same rows and the difference is far better determined than
    either MAE.
    """
    base = np.abs(test.of(BASE))
    out = {n: {"overall": score.stats(test.of(n)),
               "buckets": _by_bucket(test, test.of(n))} for n in test.names}
    for rule in rules:
        t0 = time.time()
        rule.fit(train)
        out[rule.name] = _scored(test, rule.error(test), base)
        out[rule.name]["fit_s"] = time.time() - t0
        out[rule.name]["weights"] = rule.table()
    for name, err in (extra or {}).items():
        out[name] = _scored(test, err, base)
    for name, r in out.items():
        d = (f"({r['delta']:+.1f} [{r['ci'][0]:+.1f}, {r['ci'][1]:+.1f}])"
             if "ci" in r else "")
        print(f"{name:<14} MAE {r['overall']['mae']:>6.1f} s {d}")
    return out


def _scored(test, err, base):
    lo, hi = score.bootstrap(np.abs(err) - base, test.trip)
    return {"overall": score.stats(err), "buckets": _by_bucket(test, err),
            "delta": float(np.abs(err).mean() - base.mean()),
            "ci": [float(lo), float(hi)]}


def _by_bucket(p, err):
    out = {}
    for lo, hi in score.BUCKETS:
        m = (p.horizon >= lo) & (p.horizon < hi)
        if m.any():
            out[f"{lo // 60}-{hi // 60}"] = score.stats(err[m])
    return out


def correlation(p):
    """How alike the members' errors are, which bounds what a blend can win."""
    c = np.corrcoef(p.err)
    return {a: {b: float(c[i, j]) for j, b in enumerate(p.names)}
            for i, a in enumerate(p.names)}


def rules():
    return [Blend("stack", "l2"), Blend("stack-robust", "l1"),
            Blend("debias", "l1", only=()), Median()]


def main(members=MEMBERS, fit_to=None, test_from=None, feats="reports/feats.npz",
         out=REPORTS, label="", db=replay.DB, **kw):
    fit_to = fit_to or residual._when(residual.FIT_TO)
    test_from = test_from or residual._when(residual.TEST_FROM)
    named, truth = series(members=members, db=db, **kw)
    p = panel(named, truth)
    train, test = split(p, fit_to, test_from)
    print(f"\n{len(train)} training rows, {len(test)} test rows, "
          f"{len(np.unique(test.event))} test crossings, "
          f"members {', '.join(p.names)}\n")

    extra = {}
    if feats and os.path.exists(feats):
        name, err = hybrid(features.load(feats), test, fit_to, test_from)
        extra[f"{BASE}+{name.split('-')[-1]}"] = err
    res = evaluate(train, test, rules(), extra)
    report(res, p, train, test, out, label)
    return res


def report(res, p, train, test, out, label=""):
    os.makedirs(out, exist_ok=True)
    stem = "stack" + (f"-{label}" if label else "")
    payload = {"train_rows": len(train), "test_rows": len(test),
               "test_crossings": int(len(np.unique(test.event))),
               "split": [float(train.epoch.max()), float(test.epoch.min())],
               "members": list(p.names), "correlation": correlation(test),
               "rules": res}
    with open(os.path.join(out, f"{stem}.json"), "w") as f:
        json.dump(payload, f, indent=1, sort_keys=True)

    base = res[BASE]["overall"]["mae"]
    order = sorted(res, key=lambda n: res[n]["overall"]["mae"])
    lines = ["# Blending the predictors", "",
             f"Weights fitted on the {len(train)} predictions emitted from "
             f"{residual._stamp(train.epoch.min())} to "
             f"{residual._stamp(train.epoch.max())}, and everything scored on "
             f"the {len(test)} emitted from {residual._stamp(test.epoch.min())} "
             f"to {residual._stamp(test.epoch.max())}, covering "
             f"{payload['test_crossings']} crossings. Members and blends answer "
             "the identical rows, so the interval is on the difference from "
             f"`{BASE}` rather than on either MAE.", "",
             "| predictor | MAE s | vs full | 95% CI on the difference | "
             "median s | bias s | <60 s |", "|---|---|---|---|---|---|---|"]
    for n in order:
        r, o = res[n], res[n]["overall"]
        ci = (f"{r['ci'][0]:+.1f} .. {r['ci'][1]:+.1f}" if "ci" in r else "-")
        lines.append(f"| {n} | {o['mae']:.1f} | "
                     f"{100 * (o['mae'] - base) / base:+.1f}% | {ci} | "
                     f"{o['median']:.0f} | {o['bias']:+.0f} | "
                     f"{100 * o['p60']:.1f}% |")

    lines += ["", "## By horizon, MAE in seconds", "",
              "| predictor | " + " | ".join(f"{lo // 60}-{hi // 60}"
                                            for lo, hi in score.BUCKETS) + " |",
              "|---" * (1 + len(score.BUCKETS)) + "|"]
    for n in order:
        cells = [residual._cell(res[n]["buckets"].get(f"{lo // 60}-{hi // 60}"))
                 for lo, hi in score.BUCKETS]
        lines.append(f"| {n} | " + " | ".join(cells) + " |")

    lines += ["", "## How alike the members are, on the test window", "",
              "A blend can only win where the errors disagree. Correlations "
              "near one mean the members are making the same mistake and there "
              "is nothing to average away.", "",
              "| | " + " | ".join(p.names) + " |",
              "|---" * (1 + len(p.names)) + "|"]
    for a, row in payload["correlation"].items():
        lines.append(f"| {a} | " + " | ".join(f"{row[b]:.2f}" for b in p.names) + " |")

    for n in order:
        w = res[n].get("weights")
        if not w:
            continue
        lines += ["", f"## The weights `{n}` fitted", "",
                  "| horizon | " + " | ".join(p.names) + " | intercept s |",
                  "|---" * (2 + len(p.names)) + "|"]
        for horizon, row in w.items():
            cells = " | ".join(f"{row['weights'][m]:+.2f}" for m in p.names)
            lines.append(f"| {horizon} min | {cells} | "
                         f"{row['intercept']:+.0f} |")
    with open(os.path.join(out, f"{stem}.md"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"\n-> {os.path.join(out, stem + '.md')}")
