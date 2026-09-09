"""Every rule in `commuterlviv/overrides.toml`, against the feed as it is now.

    python3 check_overrides.py

Builds the network from scratch - the cache is bypassed, so this says what a
fresh start would do - and asserts, for each rule, that the stop landed on the
patterns the rule names and nowhere else, that the sequence it landed in is
still ordered, and that the scheduled time it was given belongs to its own
trip. A rule that stops applying because the city fixed the feed fails here
first, which is the moment to delete it.
"""
import sys

import numpy as np

from commuterlviv import network, overrides

net = network.load(rebuild=True)
rules = overrides.Overrides.load().rules
ok, bad = [], []


def check(name, cond, extra=""):
    (ok if cond else bad).append(name)
    print(("PASS " if cond else "FAIL ") + name, extra)


for rule in rules:
    short, code = rule["route"], rule["stop"]
    stop = overrides.stop_by_code(net, code)
    check(f"{code} is a stop in the feed", stop is not None)
    if stop is None:
        continue

    trips = [t for t, r in net.trip_route.items()
             if net.routes[r]["short"] == short and t in net.trip_stops]
    got = [t for t in trips if stop in net.trip_stops[t][0]]
    pats = {net.pattern_of[t][0] for t in got}
    check(f"{short} serves {code} on some pattern", bool(got),
          f"{len(got)} of {len(trips)} trips, shapes {sorted(pats)}")

    toward = rule.get("toward")
    if toward:
        wrong = [t for t in got if toward not in net.stops[net.trip_stops[t][0][-1]]["name"]]
        check(f"{code} is only on {short} toward {toward}", not wrong,
              f"{len(wrong)} trips on the other direction")

    ordered, dated = True, set()
    for t in got:
        ids, dist, when = net.trip_stops[t]
        i = ids.index(stop)
        ordered &= bool(np.all(np.diff(dist) > 0) and np.all(np.diff(when) >= 0))
        dated.add(int(when[i]))
    check(f"{code} keeps {short}'s stops ordered", ordered)
    check(f"{code} is scheduled per trip, not per pattern",
          len(dated) > 1 or len(got) < 2,
          f"{len(dated)} distinct times over {len(got)} trips")

print(f"\n{len(ok)} passed, {len(bad)} failed")
for b in bad:
    print("  failed:", b)
sys.exit(1 if bad else 0)
