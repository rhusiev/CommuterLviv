"""The journey planner on the made-up city, searched from on board a vehicle,
over the footpaths of `streets`."""
import dataclasses

import pytest

from commuterlviv import plan
from commuterlviv.live import app

from . import city
from .streets import DOOR, MIDDLE

NOW = city.at(city.SEARCH_AT)
VEH = city.SEARCH_VEH
# s the bus aboard is from its next stop
TO_NEXT_S = 50.0
# further from it than any walk is capped at
FAR_S = plan.TRANSFER_CAP + 60.0
AHEAD_S = 1800.0    # a change half an hour from now


def _aboard(cat, first, veh=VEH, to_next=TO_NEXT_S):
    """Vehicle `veh` on its way out, at stop `first` in `to_next` s and then
    on at the timetable's pace."""
    return city.arrivals(cat, NOW, veh, first, NOW + to_next)


def _stop(planner, i):
    return planner.cat.stop_i[f"s{i}"]


def test_a_search_from_aboard_stays_on_to_the_stop_nearest_the_door(planner):
    arrivals = _aboard(planner.cat, first=1)

    found, _ = planner.search(plan.Aboard(VEH), DOOR, arrivals, NOW)

    best = found["options"][0]
    ride, walk = best["legs"]
    assert best["aboard"] is True
    assert (ride["kind"], ride["veh"], ride["dep"]) == ("ride", VEH, NOW)
    assert (ride["a"], ride["b"]) == (_stop(planner, 0), _stop(planner, MIDDLE))
    assert ride["arr"] == NOW + TO_NEXT_S + (MIDDLE - 1) * city.LEG_S
    assert ride["backups"] == []
    assert (walk["kind"], walk["a"], walk["b"]) == ("walk", _stop(planner, MIDDLE), -1)


def test_a_next_stop_further_off_than_any_walk_still_stays_on(planner):
    arrivals = _aboard(planner.cat, first=1, to_next=FAR_S)

    got = planner.journeys(plan.Aboard(VEH), DOOR, arrivals, NOW, None, True)

    ride = got[0].legs[0]
    assert (ride.kind, ride.veh, ride.b) == ("ride", VEH, _stop(planner, MIDDLE))


def test_a_ride_already_on_board_does_not_weigh_on_the_backups():
    ride = plan.Leg("ride", NOW, NOW + 60, 0, 1, 0, VEH)
    walk = plan.Leg("walk", NOW + 60, NOW + 120, 1, -1)

    assert plan.Journey((ride, walk), ((), ()), aboard=True).backup == 0
    assert plan.Journey((ride, walk, ride), ((), (), ()), aboard=True).backup == 0
    other = plan.Backup((ride,), NOW + 300, (0.0,), (-1,))
    backed = plan.Journey((ride, walk, ride), ((), (), (other,)), aboard=True)
    assert backed.backup == 1
    assert dataclasses.replace(backed, aboard=False).backup == 0


SOON = plan.change_slack(0)
LATER = plan.change_slack(AHEAD_S)


@pytest.mark.parametrize("legs, rushed", [
    ([("ride", NOW + SOON - 1)], True),
    ([("ride", NOW + SOON)], False),
    ([("walk", NOW + 30), ("ride", NOW + 30 + plan.change_slack(30) - 1)], True),
    ([("walk", NOW + 30), ("ride", NOW + 30 + plan.change_slack(30))], False),
    ([("walk", NOW + AHEAD_S), ("ride", NOW + AHEAD_S + LATER - 1)], True),
    ([("walk", NOW + AHEAD_S), ("ride", NOW + AHEAD_S + LATER)], False),
    ([("walk", NOW + 30)], False),
])
def test_a_change_off_the_vehicle_aboard_takes_the_change_slack(legs, rushed):
    built = [plan.Leg(kind, t, t, 0, 1) for kind, t in legs]

    assert plan._rushed(built, NOW, NOW) is rushed


def test_a_change_further_ahead_needs_more_slack():
    assert SOON == plan.CHANGE_SLACK[0]
    assert plan.change_slack(-60) == SOON
    assert SOON < plan.change_slack(plan.CHANGE_AHEAD[2]) < LATER
    assert plan.change_slack(10 * AHEAD_S) == plan.CHANGE_SLACK[-1]


def test_a_way_not_on_the_vehicle_aboard_does_not_say_it_is_ridden(planner):
    arrivals = _aboard(planner.cat, first=1)

    found, _ = planner.search(plan.Aboard(VEH), DOOR, arrivals, NOW)

    for option in found["options"]:
        assert option.get("aboard", False) == (option["legs"][0].get("veh") == VEH)


def test_getting_off_at_the_next_stop_rides_there_first(planner):
    arrivals = _aboard(planner.cat, first=MIDDLE)

    got = planner.journeys(plan.Aboard(VEH), DOOR, arrivals, NOW, None, True)

    legs = [(leg.kind, leg.a, leg.b) for leg in got[0].legs]
    middle = planner.tt.stop_i[f"s{MIDDLE}"]
    assert legs == [("ride", planner.tt.stop_i[f"s{MIDDLE - 1}"], middle, ),
                    ("walk", middle, -1)]
    assert got[0].legs[0].veh == VEH


def test_a_vehicle_at_its_first_stop_starts_the_ride_there(planner):
    arrivals = _aboard(planner.cat, first=0)

    got = planner.journeys(plan.Aboard(VEH), DOOR, arrivals, NOW, None, True)

    first = got[0].legs[0]
    assert (first.kind, first.veh, first.a) == ("ride", VEH, planner.tt.stop_i["s0"])
    assert first.dep == NOW


def test_a_vehicle_nobody_tracks_has_no_journeys(planner):
    arrivals = _aboard(planner.cat, first=1)

    assert planner.journeys(plan.Aboard(VEH + 1), DOOR, arrivals, NOW, None, True) == []


@pytest.mark.parametrize("query, origin", [
    ({"veh": "12"}, plan.Aboard(12)),
    ({"veh": "12", "from": f"{city.LAT},{city.LON}"}, plan.Aboard(12)),
    ({"veh": "x"}, None),
    ({"veh": "1" * 10}, None),
    ({"from": f"{city.LAT},{city.LON}"}, (city.LAT, city.LON)),
])
def test_the_plan_endpoint_reads_the_origin(query, origin):
    assert app._origin(query) == origin


class _NoWalks:
    def near(self, i, limit):
        return iter(())


@pytest.mark.parametrize("ahead_s", [0.0, AHEAD_S])
@pytest.mark.parametrize("short_s, rides", [(1, 0), (0, 2)])
def test_the_scan_changes_only_with_the_slack_its_time_ahead_needs(
        ahead_s, short_s, rides):
    off = NOW + TO_NEXT_S + ahead_s
    on = off + plan.change_slack(off - NOW) - short_s
    # one trip 0 -> 1 and another 1 -> 2, the door at stop 2
    hops = ([1, 0], [2, 1], [on, NOW], [on + TO_NEXT_S, off], [1, 0])
    trips = {0: ("a", None, None), 1: ("b", None, None)}
    scan = plan._Profile(hops, trips, {}, _NoWalks(), {2: 0.0}, (FAR_S,), 2, {},
                         NOW)

    found = scan.options({0: 0.0}, NOW)

    assert [j.rides for j, _ in found] == ([rides] if rides else [])
