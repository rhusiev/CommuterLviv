"""Backups counted by when they leave the stop, not by when the journey
arrives: on the made-up city's timetable, whose trips t1 and t3 leave 40 min
apart on the one route."""
from commuterlviv.plan import scan

from . import city
from .streets import DOOR

END = city._point(city.LENGTH)
# s before t1 leaves its first stop: time to walk there from the door
EARLY_S = 600.0
GAP_S = city.DEPARTS["t3"] - city.DEPARTS["t1"]


def _waits(planner):
    """Seconds after the ride boarded that each of its backups leaves, for the
    option that boards t1 wherever the door's walk reaches it."""
    now = city.at(city.DEPARTS["t1"]) - EARLY_S
    found = planner.journeys(DOOR, END, None, now, None, False)
    j = next(j for j in found if j.rides)
    k = next(k for k, leg in enumerate(j.legs) if leg.kind == "ride")
    return [b.rides[0].dep - j.legs[k].dep for b in j.backups[k]]


def test_the_next_run_within_the_window_of_leaving_is_a_backup(planner):
    assert GAP_S < scan.BACKUP_WINDOW
    # t3 reaches the door 40 min after t1, past the old "half an hour after
    # the journey arrives"; it leaves within the window, which is what counts
    assert GAP_S in _waits(planner)


def test_a_run_leaving_past_the_window_is_no_backup(planner, monkeypatch):
    monkeypatch.setattr(scan, "BACKUP_WINDOW", GAP_S - 60.0)

    assert GAP_S not in _waits(planner)
