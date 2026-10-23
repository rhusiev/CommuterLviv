"""The planner's files read in, the timetable rebuilt only for a new network."""
import pickle

from .. import files, network, walk as footpaths
from .timetable import Timetable
from .transfers import DATA, TRANSFERS, Transfers


def load(net=None):
    """The three pieces a search needs; the timetable is built and cached here."""
    net = net or network.load()
    cache = DATA / "timetable.pkl"
    tt = None
    if cache.exists():
        with open(cache, "rb") as fh:
            tt = pickle.load(fh)
    if (getattr(tt, "version", 0) != Timetable.VERSION
            or getattr(tt.net, "source", None) != net.source):
        tt = Timetable(net)
        with files.replacing(cache) as fresh, open(fresh, "wb") as fh:
            pickle.dump(tt, fh, protocol=5)
    walk, transfers = footpaths.load(), Transfers.load()
    if why := transfers.stale(tt, walk):
        raise FileNotFoundError(
            f"{TRANSFERS} is stale: {why} - run `python -m commuterlviv plan "
            "--build` once to walk between every pair of stops")
    return tt, walk, transfers
