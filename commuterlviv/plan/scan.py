"""The profile scan backwards from the door, and the slack a change needs."""
import bisect
import dataclasses
import math

import numpy as np

from .journey import Backup, Journey, Leg, _onward
from .ranking import _near, _score


# s of slack a change needs over and above the walk, by how far ahead it is:
# the forecasts of both vehicles miss by more the further out they are. Measured
# on a replay of 2026-09-16..21 (docs/service.md): each is where at most 15% of
# changes between two tracked vehicles broke (15% is chosen, not derived), at
# the middle of its band of 0-2/2-5/5-10/10-15/15-20/20-30/30-45 min ahead, and
# read between them. Copied into the clients' `follow`, for the pace hurrying needs
CHANGE_AHEAD = (60.0, 210.0, 450.0, 750.0, 1050.0, 1500.0, 2250.0)
CHANGE_SLACK = (60.0, 90.0, 150.0, 180.0, 210.0, 270.0, 300.0)
# the same, per whole second ahead, for the scan's inner loop; past the last
# band the slack stays at its last
_SLACK_BY_S = np.interp(np.arange(int(CHANGE_AHEAD[-1]) + 1), CHANGE_AHEAD,
                        CHANGE_SLACK).tolist()

# s after the journey's arrival within which another way to the door still
# counts as a backup: missing the bus stings less when the next way is soon
BACKUP_WINDOW = 1800.0

# s a tracked vehicle may leave before somebody walking to it gets there and
# still be caught, waving to its driver. Caught only by hurrying, all the
# same: better to hurry than to count on the driver. Chosen, not derived
GRACE = 10.0


def change_slack(ahead):
    """Seconds of slack a change `ahead` s from now needs (`CHANGE_SLACK`)."""
    return _SLACK_BY_S[min(max(int(ahead), 0), len(_SLACK_BY_S) - 1)]


def _quickest(access, hurry):
    """`access`, stop -> seconds walked, as soon as hurrying and waving to the
    driver (GRACE) could get there."""
    return {u: max(t * hurry - GRACE, 0.0) for u, t in access.items()}


class _Profile:
    """The search: a profile connection scan (Dibbelt, Pajor, Strasser and
    Wagner, 2013) run backwards from the door, in which every hop of every
    trip, latest first, learns the earliest door arrival from riding it in at
    most 1, 2 ... `rounds` rides, with every walk capped at each of `caps`
    (longest first) - one scan for all the caps, the i-th at slot
    `i * rounds + rides - 1` - and each stop keeps the departures worth
    boarding.

    Tracked vehicles ride at their predictions, and a scheduled departure a
    tracked vehicle is running is not boarded. A change needs the slack its
    time ahead of `now` does (`change_slack`).
    """

    def __init__(self, hops, trips, trust, transfers, egress, caps, rounds,
                 covered, now):
        self.now = now
        self.hops, self.trips, self.trust = hops, trips, trust
        self.transfers, self.egress = transfers, egress
        self.caps, self.rounds = caps, rounds
        self.n = n = len(caps) * rounds
        none = ((math.inf,) * n, (None,) * n)
        stay = {}       # trip -> per slot, door arrival riding on, and how
        # hop -> the same, how being (alighted, next (hop, slot), walked)
        self.via = {}
        # stop -> latest first: -departure, (door, hop)
        self.deps, self.profile = {}, {}
        self.steps = {}     # stop -> (walked, stop, caps allowing it)
        self.boards = []    # every (stop, departure, hop) boarded
        self.beside = {}    # stop -> see `_beside`
        for c, (u, v, d, a, t) in enumerate(zip(*hops)):
            door, how = map(list, stay.get(t, none))
            self._alight(c, v, a, door, how)
            self._fewer(door, how)
            self._change(c, v, a, door, how)
            self._fewer(door, how)
            if door[rounds - 1] == math.inf:
                continue
            door, how = tuple(door), tuple(how)
            stay[t] = self.via[c] = door, how
            route, veh, _ = trips[t]
            if veh is not None or d > covered.get((u, route), -math.inf):
                self._board(u, d, c, door)

    def _alight(self, c, v, a, door, how):
        """Off hop `c` at `v` and on foot to the door: a first ride."""
        if (e := self.egress.get(v)) is None:
            return
        rounds = self.rounds
        for cap in range(sum(e <= x for x in self.caps)):
            if a + e < door[cap * rounds]:
                door[cap * rounds], how[cap * rounds] = a + e, (c, None, e)

    def _change(self, c, v, a, door, how):
        """Off hop `c` at `v` and onto the best departure worth boarding at a
        stop in reach: a ride more than that departure's."""
        rounds, deps, profile = self.rounds, self.deps, self.profile
        if (steps := self.steps.get(v)) is None:
            steps = self.steps[v] = sorted(
                (x, w, sum(x <= y for y in self.caps))
                for w, x in [(v, 0.0), *self.transfers.near(v, self.caps[0])])
        slack = change_slack(a - self.now)
        for walk, w, ok in steps:
            x = walk + slack
            # a slot of a shorter cap is never ahead of a longer one's
            if a + x >= door[(ok - 1) * rounds + 1]:
                break
            at = deps.get(w)
            if at is None or at[0] > -(a + x):
                continue
            then, hop = profile[w][bisect.bisect_right(at, -(a + x)) - 1]
            for i in range(ok * rounds):
                if i % rounds and then[i - 1] < door[i]:
                    door[i], how[i] = then[i - 1], (c, (hop[i - 1], i - 1), walk)

    def _fewer(self, door, how):
        """A slot no better than the one with a ride fewer takes that one."""
        rounds = self.rounds
        for i in range(self.n):
            if i % rounds and door[i - 1] <= door[i]:
                door[i], how[i] = door[i - 1], how[i - 1]

    def _board(self, u, d, c, door):
        """Hop `c`, leaving `u` at `d`, among the departures worth boarding
        there if it beats every later one in some slot."""
        self.boards.append((u, d, c))
        at, got = self.deps.setdefault(u, []), self.profile.setdefault(u, [])
        if got:
            last, hop = got[-1]
            best = tuple(map(min, door, last))
            if best == last:
                return
            hop = tuple(c if x < y else h for x, y, h in zip(door, last, hop))
            door = best
        else:
            hop = (c,) * self.n
        if at and at[-1] == -d:
            got[-1] = door, hop
        else:
            at.append(-d)
            got.append((door, hop))

    def chain(self, c, i):
        """The way boarding hop `c` at slot `i`: per ride, the hop boarded,
        the hop alighted from and the seconds walked after it."""
        out = []
        while c is not None:
            e, nxt, walked = self.via[c][1][i]
            out.append((c, e, walked))
            c, i = nxt or (None, 0)
        return tuple(out)

    def ride(self, c, e):
        dep_s, arr_s, dep_t, arr_t, trip_of = self.hops
        route, veh, turns = self.trips[trip_of[c]]
        if veh is None:
            confidence = self.trust.get(route, "schedule")
        else:
            confidence = "terminus" if dep_t[c] >= turns else "live"
        return Leg("ride", dep_t[c], arr_t[e], dep_s[c], arr_s[e], route, veh,
                   veh is not None, confidence)

    def options(self, access, now):
        """For each slot, the soonest door arrival from a stop the origin
        walks to, the shortest walk winning a tie, as a journey with its way."""
        best = {}
        for u, t in sorted(access.items(), key=lambda x: x[1]):
            at = self.deps.get(u)
            if at is None or at[0] > -(now + t):
                continue
            door, hop = self.profile[u][bisect.bisect_right(at, -(now + t)) - 1]
            for i in range(sum(t <= x for x in self.caps) * self.rounds):
                if door[i] < best.get(i, (math.inf,))[0]:
                    best[i] = door[i], u, t, hop[i]
        found = {}
        for i, (_, u, t, c) in best.items():
            way = self.chain(c, i)
            if (u, way) not in found:
                found[(u, way)] = self._journey(u, t, now, way), way
        return list(found.values())

    def hurrying(self, access, hurry, now, found):
        """The options only hurrying to the first stop catches, as `options`
        gives them: read at the stops reached at `hurry` times the walk of
        `access`, and GRACE sooner, then kept where the first ride leaves
        before the usual walk gets there. One that only GRACE catches must
        ride a tracked vehicle, the only kind known to the second. Each walks
        to its stop at the hurried pace, so a little after the ride leaves for
        one GRACE catches."""
        taken = {way for _, way in found}
        out = []
        for j, way in self.options(_quickest(access, hurry), now):
            walk, ride, *rest = j.legs
            quick = now + access[walk.b] * hurry
            if way in taken or ride.dep >= now + access[walk.b] or \
                    ride.dep < quick and ride.confidence != "live":
                continue
            walk = dataclasses.replace(walk, arr=quick)
            out.append((dataclasses.replace(j, legs=(walk, ride, *rest),
                                            hurry=True), way))
        return out

    def near(self, access, now, found):
        """Per option of `found`, soonest first, a near tie of it (`_near`) as
        `options` gives journeys: the soonest at the door counting the minutes
        walked. It rides no vehicle an option or an earlier near tie rides, as
        that is no other way should the vehicle be late."""
        firsts = sorted((j for j, _ in found if j.rides), key=_score)
        trip_of, ways = self.hops[4], self._earlier(access, now, firsts)
        taken = {trip_of[c] for _, way in found for c, *_ in way}
        out = []
        for o in firsts:
            near = [(_hurried(j), n) for n, (j, way) in enumerate(ways)
                    if _near(o, j.boards, j.arr)
                    and not any(trip_of[c] in taken for c, *_ in way)]
            if near:
                out.append(ways[min(near)[1]])
                taken.update(trip_of[c] for c, *_ in out[-1][1])
        return out

    def _earlier(self, access, now, firsts):
        """Every way from a stop the origin walks to that is a near tie of one
        of `firsts`, but for those `_waits` says waited for a bus with rides
        added: boardings the options pass over, as they leave earlier and
        arrive later."""
        rounds, leaves, out = self.rounds, self._leaves(), {}
        for u, d, c in self.boards:
            if (t := access.get(u)) is None or d < now + t:
                continue
            door = self.via[c][0]
            for i in range(sum(t <= x for x in self.caps) * rounds):
                arr = door[i]
                if arr == math.inf or i % rounds and arr == door[i - 1] or \
                        not any(_near(o, d, arr) for o in firsts):
                    continue
                way = self.chain(c, i)
                if (u, way) not in out and not self._waits(way, leaves):
                    out[(u, way)] = self._journey(u, t, now, way), way
        return list(out.values())

    def _journey(self, u, t, now, way):
        """The walk from the origin to `u`, `t` seconds, then `way`."""
        rides = tuple(self.ride(c, e) for c, e, _ in way)
        return Journey((Leg("walk", now, now + t, -1, u),
                        *_onward(rides, tuple(w for *_, w in way))))

    def backed(self, found):
        """Each journey with, per leg, the other ways to the door from where the
        leg boards: leaving after the chosen departure, reaching the door within
        BACKUP_WINDOW of the journey's arrival, and searched as the journey was.
        So a route parting from the chosen one short of the door counts, and so
        does one needing a change; the chosen route's next run counts, the
        chosen departure itself not, so a last bus of the day has none. Walks
        have none.

        Each sequence of routes counts once, at its soonest run. A way another
        beats - leaving no sooner, reaching the door no later, in no more rides,
        walking no more and riding no more of the journey's own vehicles - is
        left out: nobody changes twice to arrive with the bus they could have
        waited for. So is a way changing onto a vehicle that, before the way
        leaves it, calls at or a short walk beside a stop the way boarded at,
        no sooner than the way left there and walked over: that bus waited for,
        with rides added.
        """
        after = {}
        for j, _ in found:
            for leg in j.legs:
                if leg.kind == "ride":
                    after[leg.a] = min(leg.dep, after.get(leg.a, math.inf))
        ways = {u: {} for u in after}
        rounds, leaves = self.rounds, self._leaves()
        for u, d, c in self.boards:
            if d <= after.get(u, math.inf):
                continue
            door = self.via[c][0]
            for i, arr in enumerate(door):
                if arr == math.inf or i % rounds and arr == door[i - 1]:
                    continue
                way = self.chain(c, i)
                if not self._waits(way, leaves):
                    ways[u].setdefault(way, (d, arr, sum(w for *_, w in way)))
        return [dataclasses.replace(j, backups=self._backups(j, way, ways))
                for j, way in found]

    def _leaves(self):
        """When each (trip, stop) boarding leaves."""
        trip_of = self.hops[4]
        return {(trip_of[c], u): d for u, d, c in self.boards}

    def _waits(self, way, leaves):
        """Whether a later ride of `way` could have been boarded, short of
        where it is left, at or beside a stop an earlier one boards, after
        leaving then and walking over: `leaves` holds when each (trip, stop)
        boarding left."""
        dep_s, _, dep_t, _, trip_of = self.hops
        return any(dep_t[b] + x <= leaves.get((trip_of[c], w), -math.inf)
                   <= dep_t[e]
                   for k, (c, e, _) in enumerate(way)
                   for b, *_ in way[:k]
                   for w, x in self._beside(dep_s[b]))

    def _beside(self, u):
        """`u` and the stops within the shortest walk cap of it, each with the
        seconds walked there."""
        if (got := self.beside.get(u)) is None:
            got = self.beside[u] = [(u, 0.0), *self.transfers.near(u, self.caps[-1])]
        return got

    def _backups(self, j, way, ways):
        trip_of = self.hops[4]
        mine = dict(zip((trip_of[c] for c, *_ in way),
                        (i for i, leg in enumerate(j.legs) if leg.kind == "ride")))
        out = []
        for leg in j.legs:
            runs = {}
            for back, (d, arr, walked) in ways.get(leg.a, {}).items():
                if leg.kind == "ride" and leg.dep < d and \
                        arr <= j.arr + BACKUP_WINDOW:
                    routes = tuple(self.trips[trip_of[c]][0] for c, *_ in back)
                    runs.setdefault(routes, []).append((d, arr, walked, back))
            scored = []
            for held in runs.values():
                first = min(held)[0]
                for d, arr, walked, back in held:
                    if d == first:
                        planned = tuple(mine.get(trip_of[c], -1)
                                        for c, *_ in back)
                        scored.append(((d, arr, len(back), walked,
                                        sum(i >= 0 for i in planned)),
                                       back, planned))
            # whatever beats a way sorts before it, so the kept ones are
            # all it needs checking against
            scored.sort(key=lambda s: (-s[0][0], s[0][1:]))
            kept = []
            for s in scored:
                if not any(_beats(k[0], s[0]) for k in kept):
                    kept.append(s)
            out.append(tuple(
                Backup(tuple(self.ride(c, e) for c, e, _ in back), score[1],
                       tuple(w for *_, w in back), planned)
                for score, back, planned in sorted(kept)))
        return tuple(out)


def _hurried(j):
    """Door arrival plus the seconds walked, which settles near ties."""
    return j.arr + j.walking


def _beats(a, b):
    """Whether backup score `a` - departure, door arrival, rides, seconds
    walked, rides on the journey's vehicles - is another than `b` and nowhere
    worse, leaving later being better."""
    return a != b and a[0] >= b[0] and all(x <= y for x, y in zip(a[1:], b[1:]))
