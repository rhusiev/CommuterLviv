"""Sequential and parallel replay must agree exactly, not merely closely."""
import datetime
import sys
import time

import numpy as np

from lvivpred import config, network, predictors, replay
from lvivpred.truth import Truth

net = network.load()
kw = dict(warmup=1800.0,
          t_from=datetime.datetime(2026, 9, 6, 7, 0).timestamp(),
          t_to=datetime.datetime(2026, 9, 6, 8, 30).timestamp())
cfgs = [c for c in config.VARIANTS if c.name in ("full", "no-hold", "knn")]

t = time.time()
seq = {}
truth = None
for cfg in cfgs:
    _, res = replay.run(net, cfg=cfg, **kw)
    res.net = net
    if truth is None:
        truth, first = Truth(net, res), res
    seq[cfg.name] = predictors.ours(res, truth)
t_seq = time.time() - t

t = time.time()
par, ptruth, rec = replay.run_many(net, cfgs, workers=3, **kw)
t_par = time.time() - t

bad = 0
for k in ("time", "gap", "trip"):
    if not np.array_equal(getattr(truth, k), getattr(ptruth, k)):
        print(f"truth.{k} differs"); bad += 1
for n in seq:
    for f in ("event", "epoch", "horizon", "error"):
        if not np.array_equal(getattr(seq[n], f), getattr(par[n], f)):
            print(f"{n}.{f} differs"); bad += 1

for name, fn in (("api", lambda r: predictors.api(r, truth)),
                 ("lad", lambda r: predictors.lad(r, net, truth)),
                 ("schedule", lambda r: predictors.schedule(r, truth, net))):
    a, b = fn(first), fn(rec)
    if not np.array_equal(a.error, b.error):
        print(f"{name} differs off the recording stand-in"); bad += 1

print(f"sequential {t_seq:.1f}s, parallel {t_par:.1f}s on {len(cfgs)} variants")
print("identical" if not bad else f"{bad} mismatches")
sys.exit(bool(bad))
