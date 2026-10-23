"""What a search answers: journeys of walks and rides, and the backups behind
each ride."""
from dataclasses import dataclass


# weakest first, so `min` over this order is the weakest ground a journey stands on
CONFIDENCE = ("quiet", "schedule", "terminus", "live")


@dataclass(frozen=True, slots=True)
class Leg:
    """One unbroken movement. `route` and `veh` are None on a walk."""
    kind: str                # "walk" or "ride"
    dep: float               # unix seconds
    arr: float
    a: int                   # stop index, or -1 for the origin/destination
    b: int
    route: str | None = None
    veh: int | None = None
    live: bool = False

    # "live" is a vehicle being tracked, "terminus" one boarded on a trip it is
    # yet to set off on, "schedule" is the timetable on a route that is running,
    # "quiet" is the timetable on one nothing has been seen on
    confidence: str = "live"


@dataclass(frozen=True, slots=True)
class Aboard:
    """An origin on board a tracked vehicle rather than at a point; `veh` is
    its id as the arrivals hold it."""
    veh: int


@dataclass(frozen=True, slots=True)
class Backup:
    """Another way to the door from where a ride boards: the rides it takes,
    the first leaving from there, when it reaches the door and the seconds it
    walks after each ride. `planned` is, per ride, the index of the journey's
    leg riding the same vehicle, or -1. `option` is the place in the list of
    the journey riding exactly these rides, or -1."""
    rides: tuple[Leg, ...]
    arr: float
    walks: tuple[float, ...]
    planned: tuple[int, ...]
    option: int = -1

    @property
    def walk(self):
        return sum(self.walks)

    def legs(self):
        """As a journey's legs, from the stop it leaves on."""
        return _onward(self.rides, self.walks)


def _onward(rides, walks):
    """Legs riding `rides` in turn, each followed by a walk of the seconds in
    `walks` to where the next boards, or to the door after the last."""
    out = []
    for k, (ride, walked) in enumerate(zip(rides, walks)):
        out.append(ride)
        to = rides[k + 1].a if k + 1 < len(rides) else -1
        if to != ride.b:
            out.append(Leg("walk", ride.arr, ride.arr + walked, ride.b, to))
    return tuple(out)


@dataclass(frozen=True, slots=True)
class Journey:
    legs: tuple[Leg, ...]
    # per leg, the other ways to the door from where it boards
    backups: tuple[tuple[Backup, ...], ...] = ()
    # its first leg is the vehicle already being ridden
    aboard: bool = False
    # its first ride is caught only by hurrying to it (`_Profile.hurrying`)
    hurry: bool = False

    @property
    def backup(self):
        """How many ways back up the weakest ride, for the ranking to prefer.
        One catching that ride's own vehicle further along is no help when it
        does not come, so it does not count. A ride already on board needs
        none."""
        return min((sum(i not in b.planned for b in backs)
                    for i, (leg, backs) in enumerate(zip(self.legs,
                                                         self.backups))
                    if leg.kind == "ride" and not (i == 0 and self.aboard)),
                   default=0)

    @property
    def dep(self):
        return self.legs[0].dep

    @property
    def arr(self):
        return self.legs[-1].arr

    @property
    def rides(self):
        return sum(1 for leg in self.legs if leg.kind == "ride")

    @property
    def boards(self):
        """When the first ride leaves, or None on a walk."""
        return next((leg.dep for leg in self.legs if leg.kind == "ride"), None)

    @property
    def live(self):
        """True when every ride in it is a vehicle the model can see."""
        rides = [leg for leg in self.legs if leg.kind == "ride"]
        return bool(rides) and all(leg.live for leg in rides)

    @property
    def walking(self):
        return sum(leg.arr - leg.dep for leg in self.legs if leg.kind == "walk")

    @property
    def confidence(self):
        """The weakest ground any ride in it stands on."""
        return min((leg.confidence for leg in self.legs if leg.kind == "ride"),
                   key=CONFIDENCE.index, default="live")
