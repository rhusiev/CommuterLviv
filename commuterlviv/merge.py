"""Fold recordings made on several machines into one file.

Two collectors were running for a while - one on the VPS, one at home - and
neither recording is a superset of the other. The rule for putting them
together is that the first source wins any instant it already covers: a later
source is only read where the earlier one has a hole. That is what keeps the
merged file usable for scoring. Two pollers watching the same feed produce two
independent samples of the same seconds, and simply concatenating them would
double the apparent update rate, which is a number several predictors read.

A hole is a stretch longer than `--gap` seconds with no poll of that feed. Real
holes are outages and restarts and are minutes long; the ordinary spacing
between polls is a few seconds, so the default of 30 s separates them cleanly.

The child rows are cut by time window rather than by joining back to the poll
that produced them, because `pred.poll_ts` is not bit-identical to the matching
`poll.ts` - the two are written from the same clock reading but round
differently on the way into SQLite. A window padded by a second is exact enough
and costs one scan per table.
"""
import argparse
import os
import sqlite3
import time

import numpy as np

from .collect import DB, SCHEMA

GAP = 30.0        # s without a poll before the recording counts as holed
PAD = 1.0         # s a kept window is widened by, to catch its own child rows
TABLES = (("poll", "ts"), ("veh", "poll_ts"), ("pred", "poll_ts"),
          ("lad", "poll_ts"))
FEED = {"poll": None, "veh": "veh", "pred": "pred", "lad": "lad"}


def _polls(db, feed, where="main"):
    rows = db.execute(f"SELECT ts FROM {where}.poll WHERE feed=? ORDER BY ts",
                      (feed,)).fetchall()
    return np.fromiter((r[0] for r in rows), float, len(rows))


def _windows(have, want, gap):
    """The stretches of `want` that `have` is not already within `gap` of."""
    if not len(want):
        return []
    if not len(have):
        keep = np.ones(len(want), bool)
    else:
        right = np.searchsorted(have, want)
        left = np.clip(right - 1, 0, len(have) - 1)
        right = np.clip(right, 0, len(have) - 1)
        keep = np.minimum(np.abs(want - have[left]),
                          np.abs(have[right] - want)) > gap
    if not keep.any():
        return []
    starts = np.flatnonzero(keep & ~np.r_[False, keep[:-1]])
    ends = np.flatnonzero(keep & ~np.r_[keep[1:], False])
    return [(want[a] - PAD, want[b] + PAD) for a, b in zip(starts, ends)]


def _indexes(db, make):
    for name, sql in db.execute(
            "SELECT name, sql FROM main.sqlite_master WHERE type='index'"
            " AND sql IS NOT NULL").fetchall():
        db.execute(sql if make else f"DROP INDEX {name}")


def merge(dest, sources, gap=GAP):
    out = sqlite3.connect(dest)
    out.executescript(SCHEMA)
    _indexes(out, make=False)
    out.execute("PRAGMA synchronous=OFF")
    for path in sources:
        _take(out, path, gap)
    print("indexing", flush=True)
    out.executescript(SCHEMA)
    out.execute("PRAGMA optimize")
    out.close()


def _take(out, path, gap):
    t0 = time.time()
    out.execute("ATTACH ? AS src", (os.fspath(path),))
    out.execute("CREATE TEMP TABLE win(lo REAL, hi REAL)")
    try:
        # Every hole is measured before anything is written: importing the poll
        # rows first would fill the very holes the child tables are cut against
        feeds = [r[0] for r in out.execute(
            "SELECT DISTINCT feed FROM src.poll").fetchall()]
        holes = {f: _windows(_polls(out, f), _polls(out, f, "src"), gap)
                 for f in feeds}
        for table, column in TABLES:
            n = 0
            for feed in feeds if FEED[table] is None else [FEED[table]]:
                out.execute("DELETE FROM win")
                out.executemany("INSERT INTO win VALUES(?,?)",
                                holes.get(feed, ()))
                where = "feed=? AND " if table == "poll" else ""
                cur = out.execute(
                    f"INSERT OR IGNORE INTO main.{table}"
                    f" SELECT s.* FROM src.{table} s WHERE {where}EXISTS("
                    f"  SELECT 1 FROM win w"
                    f"  WHERE s.{column} >= w.lo AND s.{column} < w.hi)",
                    (feed,) if table == "poll" else ())
                n += cur.rowcount
            out.commit()
            print(f"{os.path.basename(path)}: {table} +{n}", flush=True)
    finally:
        out.execute("DROP TABLE temp.win")
        out.execute("DETACH src")
    print(f"{os.path.basename(path)}: {time.time() - t0:.0f}s", flush=True)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="commuterlviv merge")
    ap.add_argument("sources", nargs="+", metavar="FILE",
                    help="recordings, best first: an earlier one wins the "
                         "seconds it already covers")
    ap.add_argument("--into", default=DB, metavar="FILE",
                    help=f"where the merged recording goes (default {DB})")
    ap.add_argument("--gap", type=float, default=GAP, metavar="S",
                    help="silence that counts as a hole worth filling")
    a = ap.parse_args(argv)
    if os.path.exists(a.into):
        raise SystemExit(f"{a.into} exists: merging is not resumable, "
                         "move it aside or pass another --into")
    merge(a.into, a.sources, a.gap)


if __name__ == "__main__":
    main()
