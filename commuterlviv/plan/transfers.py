"""Walking between stops: the stop-to-stop table built once and cached, and a
walk read at the stops."""
import hashlib
from pathlib import Path

import numpy as np

from .. import files, walk as footpaths


DATA = Path(__file__).resolve().parents[2] / "data"
TRANSFERS = DATA / "transfers.npz"


# longest stop-to-stop walk kept in the cached transfer table, whose size is
# quadratic in it; the search's own limit is the pure walk
TRANSFER_CAP = 900.0


def build_transfers(tt, walk, cap=TRANSFER_CAP, path=TRANSFERS):
    """Stop-to-stop walking seconds as a CSR table: one Dijkstra per stop,
    capped at `cap`, written offline to `data/transfers.npz`."""
    # a stop steps onto the footpaths just as somebody standing at it does:
    # the nearest node instead could be on the far pavement, and then
    # somebody at the pole would cross the road to board
    stands = walk.stands(tt.lat, tt.lon)
    start = [0]
    to, cost = [], []
    for i in range(len(stands.u)):
        spot = stands.spot(i)
        if spot is None:
            start.append(len(to))
            continue
        seen = walk.reach(spot.ends(), cap)
        for j, t in _at_stops(seen, stands, cap, spot).items():
            if j != i:
                to.append(j)
                cost.append(t)
        start.append(len(to))
    path.parent.mkdir(parents=True, exist_ok=True)
    # beside the one held and swapped in, as a running service may read it
    with files.replacing(path) as fresh:
        np.savez_compressed(fresh,
                            **{f"at_{k}": a for k, a in stands._asdict().items()},
                            to=np.array(to, dtype=np.int32),
                            cost=np.array(cost, dtype=np.float32),
                            start=np.array(start, dtype=np.int64),
                            model=np.array(walk.model),
                            graph=np.array(walk.graph),
                            stops=np.array(_stops_digest(tt)))
    return path


def _stops_digest(tt):
    """The stops a transfer table is numbered against, and where they stand."""
    h = hashlib.blake2b(digest_size=16)
    h.update("\n".join(tt.stops).encode())
    h.update(tt.lat.tobytes())
    h.update(tt.lon.tobytes())
    return h.hexdigest()


class Transfers:
    __slots__ = ("stands", "to", "cost", "start", "model", "graph", "stops")

    def __init__(self, stands, to, cost, start, model, graph="", stops=""):
        # where each stop steps onto the footpaths, None in a table from
        # before stops were placed on edges
        self.stands, self.to, self.cost, self.start = stands, to, cost, start
        # the `Walk.model` and `Walk.graph` it was walked on, and the stops
        # it was walked between; empty in a table from before they were noted
        self.model, self.graph, self.stops = model, graph, stops

    @classmethod
    def load(cls, path=TRANSFERS):
        if not path.exists():
            raise FileNotFoundError(
                f"{path} is not there - run `python -m commuterlviv plan "
                "--build` once to walk between every pair of stops")
        with np.load(path) as z:
            stands = None
            if "at_u" in z.files:
                stands = footpaths.Stands(*(z[f"at_{k}"]
                                            for k in footpaths.Stands._fields))
            return cls(stands, z["to"], z["cost"], z["start"],
                       *(str(z[k]) if k in z.files else ""
                         for k in ("model", "graph", "stops")))

    def paced(self, pace):
        """The table for somebody walking `pace` times as long."""
        return Transfers(self.stands.paced(pace), self.to, self.cost * pace,
                         self.start, self.model, self.graph, self.stops)

    def stale(self, tt, walk):
        """Why the table cannot be read against this timetable and walk, or
        None. It is numbered against the stop list it was built with, and a
        rebuilt network (a new feed, a changed override) may move, add or drop
        stops while keeping their number; and walked on one footpath graph,
        which a refetch replaces."""
        if self.stands is None:
            return "it predates placing stops on the footpaths' edges"
        stops = len(self.start) - 1
        if stops != len(tt.stops) or len(self.stands.u) != len(tt.stops):
            return f"it lists {stops} stops against {len(tt.stops)} in the timetable"
        if not self.stops or not self.graph:
            return "it predates noting the stops and footpaths it was walked on"
        if self.stops != _stops_digest(tt):
            return "the timetable's stops have changed since"
        if self.graph != walk.graph:
            return "the footpaths have been refetched since"
        if self.model != walk.model:
            return (f"it was walked at {self.model or 'an older model'}, "
                    f"the footpaths now at {walk.model}")
        return None

    def near(self, i, limit):
        # A table built against an older stop list is shorter than the
        # timetable; `load` refuses that combination, so reaching here means a
        # caller bug rather than a stale file - but a journey search must never
        # turn it into a 500, only into a missing walk.
        if i < 0 or i + 1 >= len(self.start):
            return
        lo, hi = self.start[i], self.start[i + 1]
        for k in range(lo, hi):
            t = float(self.cost[k])
            if t <= limit:
                yield int(self.to[k]), t


def _reach(walk, spot, limit):
    """Walking seconds from a `walk.attach` spot to every node, inf past `limit`."""
    return walk.reach(spot.ends() if spot else [], limit)


def _at_stops(seen, stands, limit, spot=None):
    """A reach from `spot` read at the stops: stop -> seconds."""
    t = stands.read(seen, spot)
    ok = np.flatnonzero(t <= limit)
    return dict(zip(ok.tolist(), t[ok].tolist()))
