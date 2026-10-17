"""Journeys caught only by hurrying to the first stop, on the made-up city:
from the door up the side street to the middle stop, then out along the road
to the end of the line."""
import numpy as np
import pytest

from commuterlviv import plan
from commuterlviv.live import app
from commuterlviv.live.state import Arrivals

from . import city
from .streets import DOOR, MIDDLE

NOW = city.at(city.SEARCH_AT)
VEH = city.SEARCH_VEH
END = city._point(city.LENGTH)
USUAL_KMH = 5.0
# fast enough to halve the walk to the middle stop
HURRY_KMH = 2 * USUAL_KMH
# s a vehicle leaves before somebody walking at the usual pace gets there:
# within GRACE, then past it and caught only at the hurry pace
WAVED_S = plan.GRACE / 2
RUN_FOR_S = 30.0


def _arrivals(cat, at_middle):
    """Vehicle VEH on its way out, at the middle stop at `at_middle` and on to
    the end of the line at the timetable's pace."""
    return city.arrivals(cat, NOW, VEH, MIDDLE, at_middle)


def _walk_to_middle(planner, now=NOW):
    """s walked from the door to the middle stop at USUAL_KMH."""
    found = planner.journeys(DOOR, END, _arrivals(planner.cat, 0), now,
                             USUAL_KMH, True)
    middle = planner.tt.stop_i[f"s{MIDDLE}"]
    walk = next(j.legs[0] for j in found if j.rides and j.legs[0].b == middle)
    return walk.arr - walk.dep


def _search(planner, before_s, hurry=None, now=NOW):
    """The options on the wire with VEH leaving the middle stop `before_s`
    before somebody walking there at the usual pace gets there."""
    at = int(now + _walk_to_middle(planner, now) - before_s)
    found, ways = planner.search(DOOR, END, _arrivals(planner.cat, at), now,
                                 USUAL_KMH, hurry)
    return found["options"], ways


def _on_veh(options):
    return [o for o in options if any(x.get("veh") == VEH for x in o["legs"])]


def test_a_tracked_bus_missed_by_less_than_the_grace_is_a_hurry_option(planner):
    options, _ = _search(planner, WAVED_S)

    caught = _on_veh(options)
    assert caught and all(o.get("hurry") for o in caught)
    walk, ride = caught[0]["legs"][:2]
    assert walk["arr"] == ride["dep"]


def test_a_bus_the_usual_walk_catches_needs_no_hurrying(planner):
    options, _ = _search(planner, -RUN_FOR_S)

    caught = _on_veh(options)
    assert caught and not any(o.get("hurry") for o in caught)


def test_a_bus_missed_by_more_than_the_grace_needs_a_hurry_pace(planner):
    calm, _ = _search(planner, RUN_FOR_S)
    hurried, _ = _search(planner, RUN_FOR_S, HURRY_KMH)

    assert _on_veh(calm) == []
    caught = _on_veh(hurried)
    assert caught and all(o.get("hurry") for o in caught)
    walk, ride = caught[0]["legs"][:2]
    assert walk["arr"] <= ride["dep"]


def test_a_scheduled_bus_is_not_caught_by_waving(planner):
    first = city.at(city.FLEET[0][2]) + MIDDLE * city.LEG_S
    walked = _walk_to_middle(planner)
    # the soonest scheduled run leaving the middle stop after NOW
    runs = np.ceil((NOW + walked - first) / city.HEADWAY_S)
    dep = first + runs * city.HEADWAY_S
    now = dep - walked + WAVED_S
    empty = _arrivals(planner.cat, 0)
    empty = Arrivals(now, empty.eta[:0], np.zeros_like(empty.start))

    found, _ = planner.search(DOOR, END, empty, now, USUAL_KMH)

    assert not any(o.get("hurry") for o in found["options"])


def test_hurry_options_leave_the_calm_ones_be(planner):
    calm, _ = _search(planner, RUN_FOR_S)
    hurried, _ = _search(planner, RUN_FOR_S, HURRY_KMH)

    assert [o for o in hurried if not o.get("hurry")] == calm


def test_a_backup_of_a_hurried_ride_walks_at_the_usual_pace(planner):
    options, ways = _search(planner, WAVED_S)
    option = next(k for k, o in enumerate(options) if o.get("hurry"))
    leg = next(k for k, x in enumerate(options[option]["legs"])
               if x.get("backups"))

    at = int(NOW + _walk_to_middle(planner) - WAVED_S)
    got = planner.backup(DOOR, END, _arrivals(planner.cat, at), USUAL_KMH, None,
                         ways[option], leg, 0)

    assert "hurry" not in got
    walk = got["legs"][0]
    assert walk["arr"] - walk["dep"] == pytest.approx(_walk_to_middle(planner),
                                                      abs=1)


@pytest.mark.parametrize("raw, kmh", [
    (None, None), ("", None), ("9", 9.0), ("x", None), ("0.1", None),
    (str(app.HURRY_KMH[1] + 1), None),
])
def test_the_plan_endpoint_reads_the_hurry_pace(raw, kmh):
    got, why = app._kmh(raw, "hurry", app.HURRY_KMH)

    assert got == kmh
    assert (why is None) == (kmh is not None or not raw)
