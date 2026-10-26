"""Which of the journeys found are offered, and in what order."""
import dataclasses
import math


# s: a way whose first ride leaves at most this much before an option's and
# reaches the door at most this much after it is an option too, though the
# other beats it - whichever comes first. Chosen, not derived
NEAR_TIE = 300.0


def _score(j):
    return j.arr, -j.backup, j.rides, j.walking, j.hurry


def _listed(found):
    """Marks each backup riding exactly what a listed journey rides with that
    journey's place in the list."""
    at = {tuple(leg for leg in j.legs if leg.kind == "ride"): n
          for n, j in enumerate(found)}

    def mark(backs):
        return tuple(dataclasses.replace(b, option=at.get(b.rides, -1))
                     for b in backs)

    return [dataclasses.replace(j, backups=tuple(map(mark, j.backups)))
            for j in found]


def _near(o, boards, arr):
    """Whether a way whose first ride leaves at `boards` and which reaches
    the door at `arr` is a near tie of journey `o`: leaving before its first
    ride by at most NEAR_TIE and arriving at most NEAR_TIE after it. Should
    `o`'s ride be late, it is the one to take."""
    return o.boards - NEAR_TIE <= boards < o.boards and arr <= o.arr + NEAR_TIE


def _rank(found, keep, walked=None):
    """Soonest first, keeping every journey no other one beats outright,
    except as a near tie of it (`_near`).

    Beaten means another is at least as good on arrival, on changes, on
    seconds spent walking and on backups: a slower journey every ride of
    which has another way behind it survives alongside the fastest hanging on
    one vehicle, which is the whole point of offering more than the fastest.
    Anything not faster than walking the way is dropped, the pure walk itself
    excepted.

    A journey riding a route nothing has been seen on is held back unless it is
    the only way of riding at all: better to be told to walk than to be sent to
    wait for a bus the city is not running. `journeys` searches those routes
    only when nothing else rides.
    """
    ceiling = math.inf if walked is None else walked
    found.sort(key=_score)
    out = []
    for j in found:
        if j.rides and j.arr - j.dep >= ceiling:
            continue
        if any(all(a <= b for a, b in zip(_score(o), _score(j))) and
               not (j.rides and o.rides and _near(o, j.boards, j.arr))
               for o in out):
            continue
        out.append(j)
    solid = [j for j in out if j.confidence != "quiet"]
    return (solid if any(j.rides for j in solid) else out)[:keep]
