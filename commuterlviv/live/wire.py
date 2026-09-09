"""How a map frame is written on the wire.

A vehicle is ten bytes: two for which vehicle, two for which route, four for
where, one for which way it points, one for whether the fix is fresh. Positions
are 16-bit offsets on a fixed box around the city, which is half a metre - far
finer than the fix itself, and a quarter of the size of the same number written
out as JSON degrees.

The box is fixed rather than derived from the data on purpose: a client decodes
a frame with no state beyond these constants, and two frames encoded a minute
apart mean the same thing.

Frames are of two kinds. A snapshot carries every vehicle the client should
have. A delta carries only the ones that moved since the client's last frame,
plus the ids that are gone. Both use the same header, so the reader is one
function.
"""
import struct

import numpy as np

VERSION = 1
SNAPSHOT, DELTA = 0, 1

LAT0, LON0 = 49.70, 23.85    # south-west corner of the encodable box
DLAT, DLON = 0.30, 0.45      # its size; 0.5 m per step at 16 bits
SCALE = 65535.0

ROW = np.dtype([("id", "u2"), ("route", "u2"), ("x", "u2"), ("y", "u2"),
                ("heading", "u1"), ("flags", "u1")])
HEADER = struct.Struct("<BBIHH")


def _frac(veh):
    return ((np.asarray(veh["lon"]) - LON0) / DLON,
            (np.asarray(veh["lat"]) - LAT0) / DLAT)


def _cell(veh):
    """A vehicle's position and heading as the wire will carry them."""
    x, y = _frac(veh)
    return ((x * SCALE).astype("u2"), (y * SCALE).astype("u2"),
            (np.rint(np.asarray(veh["heading"]) * 256.0 / 360.0).astype("u2") % 256))


def inbox(veh):
    """The vehicles the box can express. The hub filters with this before it
    diffs, so a vehicle `encode` would drop is never counted as sent."""
    x, y = _frac(veh)
    return veh[(x >= 0.0) & (x < 1.0) & (y >= 0.0) & (y < 1.0)]


def encode(veh, t, kind=SNAPSHOT, gone=()):
    """One frame. `veh` is a `state.VEH` array; `gone` are wire ids to forget.

    Vehicles outside the box are dropped rather than clipped onto its edge: a
    bus drawn on the city boundary because its fix was nonsense is worse than
    a bus that is briefly missing.
    """
    veh = inbox(veh)
    rows = np.zeros(len(veh), ROW)
    rows["id"] = veh["id"]
    rows["route"] = veh["route"]
    rows["x"], rows["y"], rows["heading"] = _cell(veh)
    rows["flags"] = veh["flags"]

    gone = np.asarray(gone, dtype="u2")
    return (HEADER.pack(kind, VERSION, int(t), len(rows), len(gone))
            + rows.tobytes() + gone.tobytes())


def decode(buf):
    """The reader the tests use, and the reference for the one in TypeScript."""
    kind, version, t, n, m = HEADER.unpack_from(buf)
    if version != VERSION:
        raise ValueError(f"frame version {version}, expected {VERSION}")
    off = HEADER.size
    rows = np.frombuffer(buf, ROW, n, off)
    gone = np.frombuffer(buf, "u2", m, off + rows.nbytes)
    return kind, t, rows, gone


def latlon(rows):
    """Decoded positions back to degrees, for tests and for the timetable."""
    return (LAT0 + rows["y"] / SCALE * DLAT, LON0 + rows["x"] / SCALE * DLON)


def changed(prev, cur):
    """Which rows a client that already has `prev` still needs, and which ids
    it should drop. Both are 16-bit id sets, so this is a sort and two joins
    rather than a dictionary walk over four hundred vehicles.

    A vehicle counts as changed when any byte of its row would change. The
    comparison is on the encoded values, not the floats behind them: a fix that
    moved by less than the half metre a step is worth encodes identically, and
    resending it would tell the client nothing.
    """
    if not len(prev):
        return cur, np.zeros(0, "u2")
    if not len(cur):
        return cur, np.asarray(prev["id"], "u2")
    order = np.argsort(prev["id"], kind="stable")
    keys = prev["id"][order]
    at = np.searchsorted(keys, cur["id"])
    hit = (at < len(keys)) & (keys[np.minimum(at, len(keys) - 1)] == cur["id"])
    same = np.zeros(len(cur), bool)
    idx = order[np.minimum(at, len(keys) - 1)]
    same[hit] = _same(prev[idx[hit]], cur[hit])
    gone = np.setdiff1d(np.asarray(prev["id"], "u2"),
                        np.asarray(cur["id"], "u2"), assume_unique=False)
    return cur[~same], gone.astype("u2")


def _same(a, b):
    ax, ay, ah = _cell(a)
    bx, by, bh = _cell(b)
    return ((a["route"] == b["route"]) & (ax == bx) & (ay == by) & (ah == bh)
            & (a["flags"] == b["flags"]))
