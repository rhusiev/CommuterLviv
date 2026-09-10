"""Model snapshots, so a restart does not begin in ignorance.

A cold model needs roughly fifteen minutes of traffic before it stops guessing,
and everything it predicts in the meantime is worse than it needs to be. A
snapshot removes that entirely: the model comes up knowing what the roads were
doing when it was last switched off.

Two details make reloading safe.

Cell indices are positional - cell 4711 means "the twelfth cell of shape X"
only for one particular build of the static feed - so a snapshot carries a
signature of the geometry it was learned on and is refused if that changed.

Age needs no check at all. Every weight is stamped with the time it was earned
and decays from that stamp, so a stale snapshot fades back to the timetable
prior on its own rather than asserting yesterday's traffic.
"""
import hashlib
import os

import numpy as np

from . import gtfs

PATH = os.path.join(gtfs.DATA, "model.npz")
PARTS = ("cf", "cs", "rf", "rs", "g")    # the terms every variant has


def signature(net, model):
    """Identifies what the stored arrays mean: the geometry the indices refer
    to, and the variant that decided what is learned per index."""
    h = hashlib.blake2b(digest_size=16)
    h.update(f"{model.cfg.name}|".encode())
    for sid in sorted(net.shapes):
        s = net.shapes[sid]
        h.update(f"{sid}:{s.cells}:{s.length:.1f};".encode())
    return h.hexdigest()


def _ewmas(model):
    """Every learned array in the model, named. The only place that reaches
    into the model's internals, so the model itself stays free of storage.

    The optional terms are named the same way and simply absent from a variant
    that does not have them; which ones exist follows from the variant, and the
    variant is part of the signature, so a snapshot can never be read back into
    a model with a different set."""
    for layer in ("pace", "hold"):
        one = getattr(model, layer)
        for part in PARTS:
            yield f"{layer}.{part}", getattr(one, part)
        for part in ("cd", "rd"):
            if getattr(one, part, None) is not None:
                yield f"{layer}.{part}", getattr(one, part)
        for i, e in enumerate(getattr(one, "pr", None) or ()):
            yield f"{layer}.pr{i}", e


def save(model, net, path=PATH):
    out = {"signature": np.array(signature(net, model))}
    for name, e in _ewmas(model):
        out[f"{name}.mean"] = e.mean
        out[f"{name}.w"] = e.w
        out[f"{name}.t"] = e.t
    tmp = path + ".tmp.npz"      # savez appends .npz unless the name has it
    np.savez_compressed(tmp, **out)
    os.replace(tmp, path)
    return path


def load(model, net, path=PATH):
    """Restore in place. Returns False if there is nothing usable to restore."""
    if not os.path.exists(path):
        return False
    with np.load(path, allow_pickle=False) as z:
        if str(z["signature"]) != signature(net, model):
            return False
        for name, e in _ewmas(model):
            e.mean = z[f"{name}.mean"]
            e.w = z[f"{name}.w"]
            e.t = z[f"{name}.t"]
    return True
