"""The search for listed stops the vehicles drive past, on made-up recordings."""
import asyncio
import time
from types import SimpleNamespace

import pytest

from commuterlviv import localtime, network, overrides, replay, skipped
from commuterlviv.live import refresh
from commuterlviv.localtime import DAY_S

from . import city

SKIPPED = 2                  # the stop the drivers of one route pass by
DAYS = 3                     # of recording, so the city's trips out are enough
TRIPS = skipped.MIN_TRIPS    # per route, in the two-route city
STAND_MPS = 0.0
PASS_MPS = 8.0
UNTIL = city.at(city.NIGHT) + (DAYS - 1) * DAY_S


def _at(i):
    """Where stop `i` of the made-up road stands."""
    return city.LAT, city.LON + i * city.GAP_M / network.KX


def _run(trip, start, served, passed=()):
    """One trip's fixes: standing at each stop of `served`, rolling through
    each of `passed`, a leg apart."""
    stops = sorted([(i, STAND_MPS) for i in served] + [(i, PASS_MPS) for i in passed])
    return [city.Fix(trip, start + k * city.LEG_S, *_at(i), v, 0.0)
            for k, (i, v) in enumerate(stops)]


def _two_routes():
    """Two bus routes along the made-up road with the same five stops listed."""
    net = network.Net()
    for i in range(city.STOPS):
        lat, lon = _at(i)
        net.stops[f"s{i}"] = {"name": f"Stop {i}", "code": str(100 + i),
                              "lat": lat, "lon": lon, "desc": ""}
    ids = tuple(f"s{i}" for i in range(city.STOPS))
    for route, short in (("rA", "А1"), ("rB", "А2")):
        net.routes[route] = {"short": short, "long": "", "type": "bus"}
        for k in range(TRIPS):
            net.trip_route[f"{route}-{k}"] = route
            net.trip_stops[f"{route}-{k}"] = (ids, None, None)
    return net


def _out(net, served, passed=(), day=city.DAY.timestamp()):
    """Every trip out along the city's road on each of `DAYS` days from the
    midnight `day`, as one vehicle each."""
    return {f"{trip}-{d}": _run(trip, day + city.DEPARTS[trip] + d * DAY_S,
                                served, passed)
            for trip, (ids, _, _) in net.trip_stops.items()
            if ids[0] == "s0" for d in range(DAYS)}


def test_a_stop_one_route_passes_is_flagged_for_that_route_alone(tmp_path):
    net = _two_routes()
    every = range(city.STOPS)
    rest = [i for i in every if i != SKIPPED]
    vehicles = {f"{route}-{k}": _run(f"{route}-{k}", city.at(city.DEPARTS["t1"])
                                     + k * city.HEADWAY_S, *served)
                for route, served in (("rA", (every,)), ("rB", (rest, [SKIPPED])))
                for k in range(TRIPS)}
    city.record(tmp_path / "feed.db", vehicles)

    found = skipped.check(net, tmp_path / "feed.db", UNTIL)

    assert [(s.route, s.stop, s.trips, s.usual) for s in found] == \
        [("А2", f"s{SKIPPED}", 0, TRIPS)]
    assert found[0].toward == f"Stop {city.STOPS - 1}"


def test_a_stop_every_trip_stood_at_is_not_flagged(net, tmp_path):
    city.record(tmp_path / "feed.db", _out(net, range(city.STOPS)))

    assert skipped.check(net, tmp_path / "feed.db", UNTIL) == []


def test_a_stop_a_remove_rule_took_off_the_route_is_not_flagged(net, tmp_path,
                                                                monkeypatch):
    rest = [i for i in range(city.STOPS) if i != SKIPPED]
    city.record(tmp_path / "feed.db", _out(net, rest, [SKIPPED]))
    rule = {"route": "А1", "stop": str(100 + SKIPPED), "toward": "Stop 4"}
    monkeypatch.setattr(overrides.Overrides, "load",
                        classmethod(lambda cls: cls(remove=[rule])))

    before = skipped.check(net, tmp_path / "feed.db", UNTIL)
    after = skipped.check(network.build(), tmp_path / "feed.db", UNTIL)

    assert [s.stop for s in before] == [f"s{SKIPPED}"]
    assert after == []


def test_a_pattern_seen_on_too_few_trips_is_not_judged(tmp_path):
    net = _two_routes()
    rest = [i for i in range(city.STOPS) if i != SKIPPED]
    few = {f"rB-{k}": _run(f"rB-{k}", city.at(city.DEPARTS["t1"]), rest, [SKIPPED])
           for k in range(TRIPS - 1)}
    city.record(tmp_path / "feed.db", few)

    assert skipped.check(net, tmp_path / "feed.db", UNTIL) == []


def test_fixes_outside_the_window_are_not_read(net, tmp_path):
    rest = [i for i in range(city.STOPS) if i != SKIPPED]
    city.record(tmp_path / "feed.db", _out(net, rest, [SKIPPED]))

    assert skipped.check(net, tmp_path / "feed.db", UNTIL + 2 * DAY_S,
                         window_s=DAY_S) == []
    assert skipped.check(net, tmp_path / "feed.db", UNTIL) != []


@pytest.mark.parametrize("end", [0, city.STOPS - 1])
def test_the_ends_of_a_pattern_are_never_flagged(net, tmp_path, end):
    rest = [i for i in range(city.STOPS) if i != end]
    city.record(tmp_path / "feed.db", _out(net, rest, [end]))

    assert skipped.check(net, tmp_path / "feed.db", UNTIL) == []


def test_the_nightly_check_keeps_what_it_found_for_the_status(net, tmp_path,
                                                             monkeypatch):
    rest = [i for i in range(city.STOPS) if i != SKIPPED]
    days_ago = localtime.midnight(time.time()) - DAYS * DAY_S
    city.record(tmp_path / "feed.db", _out(net, rest, [SKIPPED], days_ago))
    monkeypatch.setattr(replay, "DB", str(tmp_path / "feed.db"))
    s = SimpleNamespace(svc=SimpleNamespace(live=SimpleNamespace(net=net)))
    said = []

    asyncio.run(refresh.stops(s, lambda *a: said.append(" ".join(a))))

    assert [f["stop"] for f in s.skipped["stops"]] == [f"s{SKIPPED}"]
    assert s.skipped["at"] == pytest.approx(time.time(), abs=60)
    assert any("stop 102 Stop 2" in line for line in said)
