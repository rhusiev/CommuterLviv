"""Local repairs to the static feed, kept in `overrides.toml`.

The city's feed is the only statement of which route serves which stop, and it
is sometimes wrong: a route drives past a stop, calls at it, and is absent from
that stop's `stop_times` rows. Everything downstream believes the feed, so the
stop simply has no times for that route.

A rule here adds the stop back at the point the feed should have had it, before
any distance is solved, so nothing downstream needs to know an override
happened: the stop is placed on the shape by the same Viterbi assignment as the
feed's own stops, gets a scheduled time interpolated from its neighbours, and
appears in the catalogue because the catalogue is built from the stop lists.

Rules are matched against the feed on every build and skipped, loudly, when
they no longer apply.
"""
import os
import sys
import tomllib

import numpy as np

from . import network

PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "overrides.toml")

WITHIN = 50.0            # m from the line, unless the rule says otherwise


class Overrides:
    """Every rule, and which patterns each one has been applied to."""

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
        """The pattern's stops and scheduled times with every matching rule
        folded in.

        Where a stop goes depends on the pattern alone, and hundreds of trips
        share a pattern, so that much is worked out once. When it arrives is
        the trip's own business - two trips on one pattern run an hour apart -
        so the times are interpolated per trip.
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
        """Where each matching rule's stop belongs in this pattern: the index
        to insert at, and how far it sits between the two stops it lands
        between. Applied in this order, so later indexes account for earlier
        insertions."""
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
        """One line per rule, said the way a rule is written. Rules that
        matched nothing are the interesting ones: either the feed has been
        fixed or the rule never named anything real."""
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
    """Where the stop belongs in the sequence: after the last stop the line
    reaches before it, and how far along it lies between its two neighbours.

    The distances computed here only order the sequence. `network.build`
    re-solves every stop of the pattern together once the stop is in, so this
    never decides the position the model works from.
    """
    along = [network.project(shape.xy, shape.cum,
                             network.to_xy(net.stops[s]["lat"],
                                           net.stops[s]["lon"]))[0] for s in ids]
    k = int(np.searchsorted(np.maximum.accumulate(along), at))
    lo, hi = max(k - 1, 0), min(k, len(ids) - 1)
    span = along[hi] - along[lo]
    return k, min(max((at - along[lo]) / span if span > 0 else 0.0, 0.0), 1.0)
