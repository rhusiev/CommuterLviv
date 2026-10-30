"""The learned model kept on disk, so a restart or a new feed does not forget.

A cold model knows only the timetable, and the `profile` variant's hour-of-day
picture takes days of traffic to build, so losing it on every restart costs
more than a warm-up can replay.

Indices are positional - unit 4711 means "the twelfth cell of shape X" only in
one build of the feed - so a snapshot carries what each index meant: the shape
id, cell count and length behind every unit, and the corridor key behind every
corridor. Reading it back matches those against the model's network, so a new
feed keeps everything learned on the shapes and streets it did not change.
A shape cut into cells of another length (`network.Geometry.cell`) keeps them
too: each new cell takes what the old cell its middle lies in learned, its
pace as it was - a multiplier, the same for any length - and its hold in
proportion to its length, so the shape's standing adds up as before. A
corridor's and the city's hold are per crossing of a cell as well, so they are
scaled by the old cells over the new across every shape kept.

Age needs no check. Every weight is stamped with the time it was earned and
decays from that stamp, so an old snapshot fades back to the prior on its own.
"""
import time

import numpy as np

from . import files, gtfs, layover

PATH = gtfs.DATA / "model.npz"
UNIT = ("cf", "cs")             # per unit, beside the profile's `pr`
CORR = ("rf", "rs")             # per corridor
LENGTH_TOL = 0.01               # a shape longer or shorter than this has moved
LAYOVER = "layover."            # before each of `layover.FIELDS`
STANDS = "layover.rows"         # the minutes of stands its departure model learns from
PASSED = "boost.rows"           # the passed stops the ETA correction learns from
PASSED_ROUTES = "boost.routes"  # the route ids its rows number


def _ewmas(model):
    """Every learned array, named and tagged with what indexes it."""
    for layer in ("pace", "hold"):
        one = getattr(model, layer)
        for part in UNIT + CORR + ("g",):
            kind = "unit" if part in UNIT else "corr" if part in CORR else "g"
            yield f"{layer}.{part}", kind, getattr(one, part)
        for i, e in enumerate(one.pr or ()):
            yield f"{layer}.pr{i}", "unit", e


def _corridors(net):
    return np.unique(np.concatenate([net.shapes[s].corridor
                                     for s in sorted(net.shapes)]))


def export(model, t=None):
    """A copy of the model's state, cheap enough to take under the lock."""
    net = model.net
    sids = sorted(model.shape_base)
    out = {"variant": np.array(model.cfg.name),
           "t": np.array(time.time() if t is None else t),
           "shapes": np.array(sids),
           "cells": np.array([net.shapes[s].cells for s in sids]),
           "lengths": np.array([net.shapes[s].length for s in sids]),
           "corridors": _corridors(net)}
    for name, _, e in _ewmas(model):
        out[f"{name}.mean"] = e.mean.copy()
        out[f"{name}.w"] = e.w.copy()
        out[f"{name}.t"] = e.t.copy()
    for name, a in model.layovers.export().items():
        out[LAYOVER + name] = a
    out[STANDS] = model.layovers.training()
    out[PASSED] = model.boost.training()
    out[PASSED_ROUTES] = np.array(model.boost.routes)
    return out


def _within(old, new):
    """For each of `new` cells cut from a shape, the one of its `old` cells
    the new one's middle lies in."""
    return ((np.arange(new) + 0.5) * old / new).astype(int)


def _units(model, data):
    """Where each saved unit goes in `model`, and the share of its hold each
    new cell takes: its shape's old cell count over the new, 1 where the two
    agree."""
    net = model.net
    src, dst, share = [], [], []
    base = 0
    for sid, cells, length in zip(data["shapes"], data["cells"],
                                  data["lengths"]):
        sid = str(sid)
        s = net.shapes.get(sid)
        if s is not None and abs(s.length - length) <= LENGTH_TOL * length:
            src.append(base + _within(int(cells), s.cells))
            dst.append(model.shape_base[sid] + np.arange(s.cells))
            share.append(np.full(s.cells, cells / s.cells))
        base += int(cells)
    if not src:
        return np.empty(0, dtype=int), np.empty(0, dtype=int), np.empty(0)
    return np.concatenate(src), np.concatenate(dst), np.concatenate(share)


def restore(model, data):
    """Copy what still applies into a fresh model. Returns the time the state
    was taken, or None if it is another model's.

    The training rows and turnarounds hold no shape, so they are restored even
    when no shape fits any more: the recording they came from must then not
    be replayed into them again, which a None would have the caller do."""
    if str(data["variant"]) != model.cfg.name:
        return None
    if all(LAYOVER + k in data for k in layover.FIELDS):
        model.layovers.restore(*(data[LAYOVER + k] for k in layover.FIELDS))
    restore_rows(model, data)
    *unit, share = _units(model, data)
    ratio = share.mean() if share.size else 1.0

    held, now = data["corridors"], _corridors(model.net)
    at = np.minimum(np.searchsorted(held, now), len(held) - 1)
    hit = held[at] == now
    corr = at[hit], np.nonzero(hit)[0]

    for name, kind, e in _ewmas(model):
        if f"{name}.mean" not in data:
            continue
        s, d = {"unit": unit, "corr": corr}.get(kind, (slice(None),) * 2)
        for part in ("mean", "w", "t"):
            getattr(e, part)[d] = data[f"{name}.{part}"][s]
        if name.startswith("hold."):
            e.mean[d] *= share if kind == "unit" else ratio
    return float(data["t"])


def restore_rows(model, data):
    """Add the training rows `data` holds to the terminus and ETA-correction
    learners' own."""
    if STANDS in data:
        model.layovers.restore_rows(data[STANDS])
    if PASSED in data and PASSED_ROUTES in data:
        model.boost.restore_rows(data[PASSED], [str(r) for r in data[PASSED_ROUTES]])


def save(data, path=PATH):
    with files.replacing(path) as fresh:   # savez appends .npz unless it is there
        np.savez(fresh, **data)


def load(model, path=PATH):
    """Restore from disk; the time the snapshot was taken, or None."""
    if not path.exists():
        return None
    try:
        with np.load(path, allow_pickle=False) as z:
            return restore(model, z)
    except (OSError, KeyError, ValueError):
        return None
