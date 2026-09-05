"""Is the travel-time model wrong, is the tracking wrong, or is the truth wrong?

evaluate.py scores the whole pipeline: snap, filter, extrapolate, then predict.
A bias there could come from any of the four, and the yardstick itself is
measured rather than given. This separates them.

Ground truth already records the moment each vehicle crossed each stop. Take two
stops the same vehicle actually crossed, ask the model how long that should have
taken, and compare with how long it did take. No filtering, no extrapolation, no
horizon - just the model against measured road.
"""
import numpy as np

from . import network, replay, state
from .model import PACE0
from .truth import Truth


def spans(net, res, model, lo=300.0, hi=1500.0):
    """(realized seconds, modelled seconds, metres) for every observed stop pair."""
    by_run = {}
    for (vi, ti, run, si), t in res.truth.items():
        by_run.setdefault((vi, ti, run), []).append((si, t))

    out = []
    for (_, ti, _), items in by_run.items():
        trip = res.trip_ids[ti]
        shape_id = net.trip_shape[trip]
        sdist = net.trip_stops[trip][1]
        items.sort()
        for a in range(len(items)):
            for b in range(a + 1, len(items)):
                real = items[b][1] - items[a][1]
                if real < lo or real > hi:
                    continue
                d0, d1 = sdist[items[a][0]], sdist[items[b][0]]
                if d1 <= d0:
                    continue
                mod = float(model.time_between(shape_id, d0, np.array([d1]))[0])
                out.append((real, mod, d1 - d0))
    return np.array(out) if out else np.zeros((0, 3))


def position(net, res):
    """How far off is the position we predict from?

    The truth passings say where the vehicle really was: between two crossed
    stops its distance along the shape is known by interpolation. Compare that
    with the distance the filter believed at the same instant. Positive means
    the filter thought the vehicle was further along than it was, which makes
    every downstream arrival look earlier than it turns out to be.
    """
    by_run = {}
    for (vi, ti, run, si), t in res.truth.items():
        by_run.setdefault((vi, ti, run), []).append((t, si))

    curves = {}
    for k, items in by_run.items():
        if len(items) < 2:
            continue
        items.sort()
        sdist = net.trip_stops[res.trip_ids[k[1]]][1]
        curves[k] = (np.array([t for t, _ in items]),
                     np.array([sdist[i] for _, i in items], dtype=float))

    out = []
    for ep, vi, ti, run, s in res.pos:
        c = curves.get((vi, ti, run))
        if c is None:
            continue
        t = res.t0 + ep
        if t < c[0][0] or t > c[0][-1]:
            continue
        out.append(s - np.interp(t, c[0], c[1]))
    return np.array(out)


def truth_noise(truth):
    """How exact is the yardstick?

    A crossing time is interpolated between the two fixes either side of the
    stop, so it can be wrong by at most the width of that interval and in
    practice by far less. If those intervals were wide, differences of a few
    seconds between predictors would be measuring the feed, not the predictors.
    """
    g = np.sort(truth.gap)
    if not len(g):
        return
    print(f"{len(g)} crossings, seconds between the fixes each was interpolated across")
    print("  ", "  ".join(f"p{x}={g[int(x / 100 * (len(g) - 1))]:5.1f}"
                          for x in (50, 90, 99)),
          f"  max {g[-1]:.0f}\n")


def report(net=None, res=None, model=None, truth=None):
    if res is None:
        net = net or network.load()
        model = replay.PaceModel(net)
        state.load(model, net)
        model, res = replay.run(net, model=model)
        truth = Truth(net, res)

    m = model
    now = res.t0 + 1e6
    prior = m.prior_at(now)
    gr = m.pace.g.read(now)[0][0]
    gh = m.hold.g.read(now)[0][0]
    cell = float(np.mean(m.cell_len))
    gp = gr * prior.mean()
    print(f"timetable  pace {prior.mean():.4f} s/m "
          f"({3.6 / prior.mean():5.1f} km/h effective, "
          f"{100 * (m.prior != PACE0).all(axis=0).mean():.0f}% of cells timetabled, "
          f"{m.prior.max(axis=0).mean() / m.prior.min(axis=0).mean():.2f}x "
          f"slowest hour over fastest)")
    print(f"learned    pace {gp:.4f} s/m ({3.6 / gp:5.1f} km/h rolling, "
          f"{gr:.2f}x the timetable)  hold {gh:5.1f} s/cell  -> "
          f"{3.6 * cell / (gp * cell + gh):.1f} km/h effective\n")

    if truth is not None:
        truth_noise(truth)

    seen = m.pace.cs.w > 0
    print(f"cells observed at all: {seen.sum()}/{m.ncell} = "
          f"{100 * seen.mean():.1f}%")
    corr = np.zeros(m.ncorr, dtype=bool)
    corr[m.cell_corr[seen]] = True
    print(f"corridors observed:    {corr.sum()}/{m.ncorr} = {100 * corr.mean():.1f}%")
    reach = corr[m.cell_corr]
    print(f"cells backed by an observed corridor: {100 * reach.mean():.1f}%\n")

    p = position(net, res)
    if len(p):
        q = np.sort(p)
        print(f"{len(p)} position checks, believed minus actual metres along shape")
        print("  ", "  ".join(f"p{x}={q[int(x / 100 * (len(q) - 1))]:+7.0f}"
                              for x in (5, 25, 50, 75, 95)),
              f"  mean {p.mean():+.0f}\n")

    s = spans(net, res, m)
    if not len(s):
        print("no stop pairs")
        return s
    real, mod, dist = s[:, 0], s[:, 1], s[:, 2]
    err = mod - real
    print(f"{len(s)} observed stop-to-stop spans, 5-25 min apart")
    print(f"  realized  {3.6 * (dist / real).mean():5.1f} km/h door to door")
    print(f"  modelled  {3.6 * (dist / mod).mean():5.1f} km/h")
    print(f"  error (modelled - realized)  mean {err.mean():+7.0f} s  "
          f"median {np.median(err):+7.0f} s  MAE {np.abs(err).mean():6.0f} s")
    print(f"  ratio modelled/realized", end="")
    r = np.sort(mod / real)
    for p in (10, 25, 50, 75, 90):
        print(f"  p{p}={r[int(p / 100 * (len(r) - 1))]:.2f}", end="")
    print()
    return s
