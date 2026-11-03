"""When a line leaves a stop today, by the timetable, for the open line's
hours and how often it runs."""
from . import city

NOW = city.at(city.SEARCH_AT)


def test_a_line_leaves_its_first_stop_on_every_trip_that_way(planner):
    got = planner.departures(city.ROUTE, "s0", NOW)

    out = sorted(city.at(dep) for trip, sid, dep in city.TRIPS + city.FLEET
                 if sid == "out")
    assert got == out


def test_a_trip_ending_at_the_stop_does_not_leave_it(planner):
    got = planner.departures(city.ROUTE, f"s{city.STOPS - 1}", NOW)

    assert got == [city.at(city.DEPARTS["t2"])]


def test_a_stop_or_route_the_timetable_lacks_has_no_departures(planner):
    assert planner.departures(city.ROUTE, "nowhere", NOW) == []
    assert planner.departures("no-such-route", "s0", NOW) == []
