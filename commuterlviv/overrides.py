"""Local repairs to the static feed, kept in `overrides.toml`.

A rule adds a stop the feed omits from a route's pattern, or removes one the
feed lists but the route drives past, before any distance is solved, so the
rest of the build treats the pattern like any the feed spells out.
"""
import os
import sys
import tomllib

import numpy as np

from . import network

PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "overrides.toml")

WITHIN = 50.0            # m from the line, unless the rule says otherwise
ADD, REMOVE = "add", "remove"
DONE = {ADD: "added to", REMOVE: "removed from"}


class Overrides:
    def __init__(self, add=(), remove=()):
        # `rules` stays the add rules, as `check_overrides.py` reads them
        self.rules, self.removals = list(add), list(remove)
        self._rules = [(ADD, r) for r in add] + [(REMOVE, r) for r in remove]
        self.applied = {i: 0 for i in range(len(self._rules))}
        self._patched = {}

    @classmethod
    def load(cls, path=PATH):
        if not os.path.exists(path):
            return cls()
        with open(path, "rb") as f:
            rules = tomllib.load(f)
        return cls(rules.get(ADD, []), rules.get(REMOVE, []))

    def patch(self, net, route, shape_id, ids, times):
        """The pattern's stops and scheduled times with matching rules folded in.

        Placement is per pattern and cached; times are interpolated per trip.
        A stop both added and removed stays removed.
        """
        if not self._rules:
            return ids, times
        key = (route, shape_id, ids)
        plan = self._patched.get(key)
        if plan is None:
            plan = self._patched[key] = self._plan(net, route, shape_id, ids)
        inserts, drop = plan
        for k, stop, f in inserts:
            lo, hi = max(k - 1, 0), min(k, len(times) - 1)
            ids = ids[:k] + (stop,) + ids[k:]
            times = times[:k] + [round(times[lo] + (times[hi] - times[lo]) * f)] \
                + times[k:]
        if drop:
            keep = [k for k, stop in enumerate(ids) if stop not in drop]
            ids, times = tuple(ids[k] for k in keep), [times[k] for k in keep]
        return ids, times

    def _plan(self, net, route, shape_id, ids):
        """Insert index and interpolation fraction per matching add rule, in
        the order they must be applied: later indexes account for earlier
        inserts. Then the stops the remove rules take out."""
        short = net.routes.get(route, {}).get("short")
        shape = net.shapes[shape_id]
        last = net.stops[ids[-1]]["name"]
        inserts, drop = [], set()
        for i, (kind, rule) in enumerate(self._rules):
            if rule.get("route") != short:
                continue
            toward = rule.get("toward")
            if toward and toward not in last:
                continue
            stop = stop_by_code(net, rule.get("stop"))
            if kind == REMOVE:
                if stop in ids:
                    drop.add(stop)
                    self.applied[i] += 1
                continue
            if stop is None or stop in ids:
                continue
            p = network.to_xy(net.stops[stop]["lat"], net.stops[stop]["lon"])
            at, off = network.project(shape.xy, shape.cum, p)
            if off > rule.get("within", WITHIN):
                continue
            k, f = _place(net, shape, ids, at)
            inserts.append((k, stop, f))
            ids = ids[:k] + (stop,) + ids[k:]
            self.applied[i] += 1
        return inserts, drop

    def report(self):
        """One line per rule; rules that matched nothing are reported to stderr."""
        for i, (kind, rule) in enumerate(self._rules):
            where = f"{rule.get('route')} at stop {rule.get('stop')}"
            if self.applied[i]:
                print(f"override: {where} {DONE[kind]} {self.applied[i]} "
                      "pattern(s)", flush=True)
            else:
                print(f"override: {where} matched nothing and was skipped",
                      file=sys.stderr, flush=True)


def stop_by_code(net, code):
    """A stop by the code on its sign, or by its feed id if it has no code."""
    if code is None:
        return None
    for stop, v in net.stops.items():
        if v["code"] == code or stop == code:
            return stop
    return None


def _place(net, shape, ids, at):
    """Insert index for the stop, and how far it lies between its neighbours.

    These distances only order the sequence; `network.build` re-solves positions.
    """
    along = [network.project(shape.xy, shape.cum,
                             network.to_xy(net.stops[s]["lat"],
                                           net.stops[s]["lon"]))[0] for s in ids]
    k = int(np.searchsorted(np.maximum.accumulate(along), at))
    lo, hi = max(k - 1, 0), min(k, len(ids) - 1)
    span = along[hi] - along[lo]
    return k, min(max((at - along[lo]) / span if span > 0 else 0.0, 0.0), 1.0)
