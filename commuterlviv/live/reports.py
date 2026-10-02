"""Searches somebody asked to have looked at, and running one again.

Every journey search is held in memory for KEEP seconds with the predicted
arrivals it ran on, and nothing is written unless the one who searched reports
it. A report is one file in `data/reports/`: the request, those arrivals, the
catalog ids they are indexed by, the answer as it was sent, the version and a
note. `python -m commuterlviv report FILE` searches it again on the code and
timetable at hand, so a wrong answer seen on a phone can be stepped through
here, and a fix checked against it.
"""
import datetime
import json
import threading
import time
import uuid
from collections import OrderedDict
from types import SimpleNamespace

import numpy as np

from .. import __version__, gtfs, network, plan, replay
from . import journeys
from .state import Arrivals, Catalog

DIR = gtfs.DATA / "reports"
KEEP = 1800.0       # s a search can still be reported after it was made
HELD = 300          # searches held at once, city-wide
FILES = 200         # reports kept before new ones are refused
NOTE = 1000         # characters of a note


class Full(Exception):
    pass


class Recent:
    """The searches still reportable. The arrivals are shared with the live
    state, which replaces rather than mutates them, so holding one costs
    nothing past the answer itself."""

    def __init__(self):
        self.held = OrderedDict()
        self.lock = threading.Lock()

    def hold(self, user, search):
        """Keeps `search` for `user` and returns the id to report it by."""
        rid = uuid.uuid4().hex
        now = time.monotonic()
        with self.lock:
            self.held[rid] = (now, user, search)
            while self.held and (len(self.held) > HELD or
                                 next(iter(self.held.values()))[0] < now - KEEP):
                self.held.popitem(last=False)
        return rid

    def take(self, user, rid):
        """The search `rid` of `user`'s, once: a report is written at most once."""
        with self.lock:
            got = self.held.get(rid) if isinstance(rid, str) else None
            if got is None or got[1] != user or got[0] < time.monotonic() - KEEP:
                return None
            del self.held[rid]
        return got[2]


def write(search, note, user, folder=DIR):
    """The report's file name. `search` is what `Recent.hold` was given."""
    folder.mkdir(parents=True, exist_ok=True)
    if sum(1 for _ in folder.glob("*.npz")) >= FILES:
        raise Full
    arrivals, cat = search["arrivals"], search["cat"]
    meta = {"version": __version__, "user": str(user), "note": note,
            "reported": time.time(), "catalog": cat.tag,
            "stops": cat.stops, "routes": cat.routes,
            **{k: search[k] for k in ("from", "to", "t", "asked", "speed",
                                      "answer")}}
    stamp = datetime.datetime.now(plan.TZ).strftime("%Y%m%d-%H%M%S")
    path = folder / f"{stamp}-{uuid.uuid4().hex[:6]}.npz"
    tmp = path.with_suffix(".tmp.npz")
    np.savez_compressed(tmp, eta=arrivals.eta, start=arrivals.start,
                        arrivals_t=arrivals.t, meta=json.dumps(meta))
    tmp.replace(path)
    return path.name


def read(path):
    """The report's meta, with its arrivals and catalog rebuilt."""
    with np.load(path) as z:
        meta = json.loads(str(z["meta"]))
        meta["arrivals"] = Arrivals(float(z["arrivals_t"]), z["eta"], z["start"])
    stops, routes = meta["stops"], meta["routes"]
    meta["cat"] = SimpleNamespace(
        stops=stops, routes=routes, tag=meta["catalog"],
        stop_i={s: i for i, s in enumerate(stops)},
        route_i={r: i for i, r in enumerate(routes)})
    return meta


def main(argv):
    """`python -m commuterlviv report FILE`: the answer as it was sent, then
    the one the code and timetable here give."""
    if len(argv) != 1:
        print("usage: report FILE")
        return
    r = read(argv[0])
    net = network.load()
    tt, walk, transfers = plan.load(net)
    planner = journeys.Planner(tt, walk, transfers, r["cat"])
    print(f"reported {_stamp(r['reported'])} by user {r['user']} on "
          f"v{r['version']}, here v{__version__}")
    print(f"from {r['from']} to {r['to']}, leaving {_stamp(r['t'])}, "
          f"walking {r['speed'] or 'at the usual'} km/h")
    if r["note"]:
        print(f"note: {r['note']}")
    if r["catalog"] != Catalog(net).tag:
        print("the feed has changed since: stops and trips may differ")
    found = planner.journeys(r["from"], r["to"], r["arrivals"], r["t"],
                             r["speed"], r["t"] <= r["asked"] + replay.HORIZON)
    for title, options in (("served", r["answer"]["options"]),
                           ("here", [planner.wire(j) for j in found])):
        print(f"\n== {title}: {len(options)} options")
        _show(options, r["cat"], net)


def _show(options, cat, net):
    def stop(i):
        return net.stops.get(cat.stops[i], {}).get("name", cat.stops[i]) \
            if i >= 0 else "the door"

    def ride(x):
        short = net.routes.get(cat.routes[x["route"]], {}).get("short", "?") \
            if x["route"] >= 0 else "?"
        return f"{short}@{stop(x['a'])} {plan._clock(x['dep'])}"

    for o in options:
        print(f"\n{plan._clock(o['dep'])} -> {plan._clock(o['arr'])}, "
              f"{o['rides']} rides, {o['backup']} backups")
        for leg in o["legs"]:
            if leg["kind"] == "walk":
                print(f"  walk {(leg['arr'] - leg['dep']) / 60:.0f} min to "
                      f"{stop(leg['b'])}")
                continue
            print(f"  {ride(leg)} to {stop(leg['b'])} ({plan._clock(leg['arr'])}"
                  f", {leg['confidence']})")
            for b in leg["backups"]:
                print(f"    or {' > '.join(map(ride, b['rides']))}, at the door "
                      f"{plan._clock(b['arr'])}")


def _stamp(t):
    return datetime.datetime.fromtimestamp(t, plan.TZ).strftime("%Y-%m-%d %H:%M")
