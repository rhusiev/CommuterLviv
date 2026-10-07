"""The learned model kept on disk, so a restart or a new feed does not forget.

A cold model knows only the timetable, and the `profile` variant's hour-of-day
picture takes days of traffic to build, so losing it on every restart costs
more than a warm-up can replay.

Indices are positional - unit 4711 means "the twelfth cell of shape X" only in
one build of the feed - so a snapshot carries what each index meant: the shape
id, cell count and length behind every unit, and the corridor key behind every
corridor. Reading it back matches those against the model's network, so a new
feed keeps everything learned on the shapes and streets it did not change.

Age needs no check. Every weight is stamped with the time it was earned and
decays from that stamp, so an old snapshot fades back to the prior on its own.
"""
import os
import time

import numpy as np

from . import gtfs, layover
from .model import PaceModel

PATH = gtfs.DATA / "model.npz"
UNIT = ("cf", "cs", "cd")       # per unit, beside the profile's `pr`
CORR = ("rf", "rs", "rd")       # per corridor
LENGTH_TOL = 0.01               # a shape longer or shorter than this has moved
LAYOVER = "layover."            # before each of `layover.FIELDS`


def supported(model):
    """Per-cell online models only: a section is numbered by stop pattern, and
    the other estimators keep no EWMAs."""
    return type(model) is PaceModel and model.cfg.unit == "cell"


def _ewmas(model):
    """Every learned array, named and tagged with what indexes it."""
    for layer in ("pace", "hold"):
        one = getattr(model, layer)
        for part in UNIT + CORR + ("g",):
            if (e := getattr(one, part)) is not None:
                kind = "unit" if part in UNIT else "corr" if part in CORR else "g"
                yield f"{layer}.{part}", kind, e
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
    return out


def restore(model, data):
    """Copy what still applies into a fresh model. Returns the time the state
    was taken, or None if none of it fits this model."""
    if not supported(model) or str(data["variant"]) != model.cfg.name:
        return None
    if all(LAYOVER + k in data for k in layover.FIELDS):
        model.layovers.restore(*(data[LAYOVER + k] for k in layover.FIELDS))
    net = model.net
    src, dst = [], []
    base = 0
    for sid, cells, length in zip(data["shapes"], data["cells"],
                                  data["lengths"]):
        sid = str(sid)
        s = net.shapes.get(sid)
        if (s is not None and s.cells == cells
                and abs(s.length - length) <= LENGTH_TOL * length):
            src.append(np.arange(base, base + cells))
            dst.append(model.shape_base[sid] + np.arange(cells))
        base += int(cells)
    if not src:
        return None
    unit = np.concatenate(src), np.concatenate(dst)

    held, now = data["corridors"], _corridors(net)
    at = np.minimum(np.searchsorted(held, now), len(held) - 1)
    hit = held[at] == now
    corr = at[hit], np.nonzero(hit)[0]

    for name, kind, e in _ewmas(model):
        if f"{name}.mean" not in data:
            continue
        s, d = {"unit": unit, "corr": corr}.get(kind, (slice(None),) * 2)
        for part in ("mean", "w", "t"):
            getattr(e, part)[d] = data[f"{name}.{part}"][s]
    return float(data["t"])


def save(data, path=PATH):
    tmp = path.with_suffix(".tmp.npz")     # savez appends .npz unless it is there
    np.savez(tmp, **data)
    os.replace(tmp, path)


def load(model, path=PATH):
    """Restore from disk; the time the snapshot was taken, or None."""
    if not path.exists() or not supported(model):
        return None
    try:
        with np.load(path, allow_pickle=False) as z:
            return restore(model, z)
    except (OSError, KeyError, ValueError):
        return None
