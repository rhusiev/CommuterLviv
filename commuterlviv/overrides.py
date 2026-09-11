"""Local repairs to the static feed, kept in `overrides.toml`.

A rule adds a stop the feed omits from a route's pattern, before any distance is
solved, so the rest of the build treats it like any feed stop.
"""
import os
import sys
import tomllib

import numpy as np

from . import network

PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "overrides.toml")

WITHIN = 50.0            # m from the line, unless the rule says otherwise


class Overrides:
    def __init__(self, rules):
        self.rules = rules
        self.applied = {i: 0 for i in range(len(rules))}
        self._patched = {}

    @classmethod
    def load(cls, path=PATH):
        if not os.path.exists(path):
            return cls([])
        with open(path, "rb") as f:
            return cls(tomllib.load(f).get("add", []))

    def patch(self, net, route, shape_id, ids, times):
        """The pattern's stops and scheduled times with matching rules folded in.

        Placement is per pattern and cached; times are interpolated per trip.
        """
        if not self.rules:
            return ids, times
        key = (route, shape_id, ids)
        plan = self._patched.get(key)
        if plan is None:
            plan = self._patched[key] = self._plan(net, route, shape_id, ids)
        for k, stop, f in plan:
            lo, hi = max(k - 1, 0), min(k, len(times) - 1)
            ids = ids[:k] + (stop,) + ids[k:]
            times = times[:k] + [round(times[lo] + (times[hi] - times[lo]) * f)] \
                + times[k:]
        return ids, times

    def _plan(self, net, route, shape_id, ids):
        """Insert index and interpolation fraction per matching rule, in the
        order they must be applied: later indexes account for earlier inserts."""
        short = net.routes.get(route, {}).get("short")
        shape = net.shapes[shape_id]
        plan = []
        for i, rule in enumerate(self.rules):
            if rule.get("route") != short:
                continue
            stop = stop_by_code(net, rule.get("stop"))
            if stop is None or stop in ids:
                continue
            toward = rule.get("toward")
            if toward and toward not in net.stops[ids[-1]]["name"]:
                continue
            p = network.to_xy(net.stops[stop]["lat"], net.stops[stop]["lon"])
            at, off = network.project(shape.xy, shape.cum, p)
            if off > rule.get("within", WITHIN):
                continue
            k, f = _place(net, shape, ids, at)
            plan.append((k, stop, f))
            ids = ids[:k] + (stop,) + ids[k:]
            self.applied[i] += 1
        return plan

    def report(self):
        """One line per rule; rules that matched nothing are reported to stderr."""
        for i, rule in enumerate(self.rules):
            where = f"{rule.get('route')} at stop {rule.get('stop')}"
            if self.applied[i]:
                print(f"override: {where} added to {self.applied[i]} pattern(s)",
                      flush=True)
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
