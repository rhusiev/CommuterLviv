"""`python -m commuterlviv plan`: build the transfer table once, or try one
search."""
import datetime
from itertools import zip_longest

from .. import localtime, network, walk as footpaths
from .cache import load
from .search import journeys
from .timetable import Timetable
from .transfers import build_transfers


def main(argv):
    """`python -m commuterlviv plan --build` once, then
    `python -m commuterlviv plan LAT,LON LAT,LON` to try one."""
    net = network.load()
    if "--build" in argv:
        tt = Timetable(net)
        print(f"{len(tt.patterns)} patterns over {len(tt.stops)} stops")
        print("walking between every pair of stops")
        print(build_transfers(tt, footpaths.load()))
        return
    if len(argv) < 2:
        print("usage: plan LAT,LON LAT,LON  |  plan --build")
        return
    import time
    origin, dest = [tuple(float(x) for x in a.split(",")) for a in argv[:2]]
    tt, walk, transfers = load(net)
    now = time.time()
    began = time.perf_counter()
    out = journeys(tt, walk, transfers, origin, dest, now)
    print(f"{len(out)} options in {1e3 * (time.perf_counter() - began):.0f} ms")
    for j in out:
        print(f"\n{_clock(j.dep)} -> {_clock(j.arr)}  "
              f"{(j.arr - j.dep) / 60:.0f} min, {j.rides} rides")
        for leg, backs in zip_longest(j.legs, j.backups, fillvalue=()):
            where = ("the door" if leg.b < 0
                     else net.stops[tt.stops[leg.b]]["name"])
            if leg.kind == "walk":
                print(f"  walk {(leg.arr - leg.dep) / 60:.0f} min to {where}")
            else:
                short = net.routes[leg.route]["short"]
                tag = "live" if leg.live else "timetable"
                print(f"  {_clock(leg.dep)} {short} to {where} "
                      f"({_clock(leg.arr)}, {tag})")
                for back in backs:
                    shorts = " > ".join(net.routes[r.route]["short"]
                                        for r in back.rides)
                    also = (f", option {back.option + 1}"
                            if back.option >= 0 else "")
                    print(f"    or {_clock(back.rides[0].dep)} {shorts}, "
                          f"at the door {_clock(back.arr)}{also}")


def _clock(t):
    return datetime.datetime.fromtimestamp(t, localtime.TZ).strftime("%H:%M")
