"""Close options: a way another beats only narrowly, offered when asked for,
and a report that keeps whether it was."""
from types import SimpleNamespace

from commuterlviv import plan
from commuterlviv.live import reports
from commuterlviv.live.state import Arrivals
from commuterlviv.plan.ranking import CLOSE_S, _rank

from . import city
from .streets import DOOR

NOW = city.at(city.SEARCH_AT)
KEEP = 8


def _one_ride(walk_s, boards, arr, veh, rides=1):
    """From the door: a walk to a stop, `rides` rides, a walk to the door."""
    legs = [plan.Leg("walk", NOW, NOW + walk_s, -1, 0)]
    for k in range(rides):
        legs.append(plan.Leg("ride", NOW + boards + k, NOW + arr - 60, k, k + 1,
                             "r", veh + k))
    legs.append(plan.Leg("walk", NOW + arr - 60, NOW + arr, rides, -1))
    return plan.Journey(tuple(legs), tuple(() for _ in legs))


# as the report "Where is 16?": А27 from a stop 210 s away at the door in 1620 s,
# А16 from one 306 s away, leaving after it and a minute later at the door
BEST = _one_ride(210.0, 240.0, 1620.0, veh=1)
NARROW = _one_ride(306.0, 360.0, 1680.0, veh=2)


def test_a_way_beaten_narrowly_is_offered_only_when_close_options_are_asked():
    assert _rank([BEST, NARROW], KEEP) == [BEST]
    assert _rank([BEST, NARROW], KEEP, close=True) == [BEST, NARROW]


def test_a_way_beaten_by_more_than_close_or_riding_more_is_not_close():
    late = _one_ride(306.0, 360.0, 1620.0 + CLOSE_S + 60.0, veh=2)
    changing = _one_ride(306.0, 360.0, 1680.0, veh=2, rides=2)

    assert _rank([BEST, late], KEEP, close=True) == [BEST]
    assert _rank([BEST, changing], KEEP, close=True) == [BEST]


def test_close_options_keep_every_option_of_a_search_without_them(planner):
    arrivals = city.arrivals(planner.cat, NOW, city.SEARCH_VEH, 1, NOW + 300)
    end = city._point(city.LENGTH)

    usual = planner.journeys(DOOR, end, arrivals, NOW, None, True)
    close = planner.journeys(DOOR, end, arrivals, NOW, None, True, close=True)

    assert usual and all(j in close for j in usual)


def test_a_report_keeps_what_its_search_left_out_and_whether_it_was_close(tmp_path):
    search = {"from": [49.8, 24.0], "to": [49.81, 24.04], "t": NOW, "asked": NOW,
              "speed": None, "hurry": None, "avoid": frozenset({"tram"}),
              "close": True, "answer": {"options": []},
              "arrivals": Arrivals(NOW),
              "cat": SimpleNamespace(tag="t", stops=["s0"], routes=["r1"])}

    got = reports.read(tmp_path / reports.write(search, "", "u", tmp_path))

    assert (got["avoid"], got["close"]) == (["tram"], True)
