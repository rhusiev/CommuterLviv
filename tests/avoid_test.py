"""A search that leaves out a vehicle type, on the made-up city, whose one
route is a bus: from the door to the end of the line, the bus or the walk."""
import pytest

from commuterlviv import plan
from commuterlviv.live import app

from . import city
from .streets import DOOR, MIDDLE

NOW = city.at(city.SEARCH_AT)
VEH = city.SEARCH_VEH
END = city._point(city.LENGTH)
# s the bus is from the middle stop: long enough to walk there and board
AT_MIDDLE_S = 600.0


def _arrivals(cat):
    return city.arrivals(cat, NOW, VEH, MIDDLE, NOW + AT_MIDDLE_S)


def _rides(found):
    """Every ride the options, their backups and the hurry options take."""
    for j in found:
        yield from (leg for leg in j.legs if leg.kind == "ride")
        for backs in j.backups:
            for back in backs:
                yield from back.rides


def test_a_search_avoiding_buses_rides_nothing_in_a_city_of_buses(planner):
    arrivals = _arrivals(planner.cat)

    usual = planner.journeys(DOOR, END, arrivals, NOW, None, True)
    avoided = planner.journeys(DOOR, END, arrivals, NOW, None, True,
                               avoid=frozenset({"bus"}))

    assert any(_rides(usual))
    assert avoided and not any(_rides(avoided))


def test_a_search_avoiding_trams_keeps_the_bus(planner):
    arrivals = _arrivals(planner.cat)

    found = planner.journeys(DOOR, END, arrivals, NOW, None, True,
                             avoid=frozenset({"tram"}))

    assert any(_rides(found))


def test_the_bus_already_on_board_is_ridden_though_buses_are_avoided(planner):
    arrivals = city.arrivals(planner.cat, NOW, VEH, 1, NOW + 50)

    got = planner.journeys(plan.Aboard(VEH), DOOR, arrivals, NOW, None, True,
                           avoid=frozenset({"bus"}))

    assert got and (got[0].legs[0].kind, got[0].legs[0].veh) == ("ride", VEH)


@pytest.mark.parametrize("raw, avoid, refused", [
    (None, frozenset(), False),
    ("", frozenset(), False),
    ("tram,trolleybus", frozenset({"tram", "trolleybus"}), False),
    ("boat", None, True),
    ("bus,tram,trolleybus", None, True),
])
def test_the_plan_endpoint_reads_what_to_avoid(raw, avoid, refused):
    got, why = app._avoid(raw)

    assert got == avoid
    assert (why is not None) == refused
