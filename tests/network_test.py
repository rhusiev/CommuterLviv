"""The network built from the made-up city's feed."""
import numpy as np
import pytest

from . import city


def test_stops_land_on_the_shape_where_they_stand(net):
    stops, dist, sched = net.trip_stops["t1"]

    assert stops == tuple(f"s{i}" for i in range(city.STOPS))
    assert dist == pytest.approx(np.arange(city.STOPS) * city.GAP_M, abs=1.0)
    legs = np.arange(city.STOPS) * city.LEG_S
    assert sched == pytest.approx(city.DEPARTS["t1"] + legs)


def test_the_way_back_runs_the_stops_in_reverse(net):
    stops, dist, _ = net.trip_stops["t2"]

    assert stops == tuple(f"s{i}" for i in reversed(range(city.STOPS)))
    assert dist == pytest.approx(np.arange(city.STOPS) * city.GAP_M, abs=1.0)


def test_the_block_chains_its_trips_in_timetable_order(net):
    assert net.trip_next == {"t1": "t2", "t2": "t3"}


def test_the_route_is_typed_by_its_short_name(net):
    assert net.routes[city.ROUTE]["type"] == "bus"
