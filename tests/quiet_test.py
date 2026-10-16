"""The vehicles counted against the trips the timetable has under way."""
import pytest

from commuterlviv import plan
from commuterlviv.live import quiet

from . import city

TRIP_S = city.LENGTH / city.SPEED
BUSY = city.at(9 * 3600 + 6 * city.HEADWAY_S)   # one fleet trip leaving, one arriving
NIGHT = city.at(3 * 3600)


@pytest.fixture
def tt(net):
    return plan.Timetable(net)


def _under_way(at):
    return sum(city.at(dep) <= at <= city.at(dep) + TRIP_S
               for dep in city.DEPARTS.values())


def test_the_trips_under_way_are_counted_from_the_timetable(tt):
    assert quiet.running(tt, BUSY) == _under_way(BUSY) > 0
    assert quiet.running(tt, NIGHT) == 0


def test_too_few_vehicles_for_the_trips_under_way_are_quiet(tt, monkeypatch):
    monkeypatch.setattr(quiet, "MIN_RUNNING", _under_way(BUSY))

    assert quiet.judge(0, tt, BUSY)
    assert not quiet.judge(_under_way(BUSY), tt, BUSY)


def test_too_few_trips_under_way_are_never_judged(tt, monkeypatch):
    monkeypatch.setattr(quiet, "MIN_RUNNING", _under_way(BUSY) + 1)

    assert not quiet.judge(0, tt, BUSY)
    assert not quiet.judge(0, tt, NIGHT)


def test_nothing_is_judged_without_a_timetable():
    assert not quiet.judge(0, None, BUSY)
