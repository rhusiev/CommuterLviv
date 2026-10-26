"""The route lines the clients draw and list stop by stop."""
from commuterlviv.live import geometry, state

from . import city


def _lines(net):
    cat = state.Catalog(net)
    route = geometry.describe(net, cat)["routes"][cat.route_i[city.ROUTE]]
    return cat, {line["dir"]: line for line in route["lines"]}


def test_each_way_lists_its_stops_in_the_order_it_calls_at_them(net):
    cat, lines = _lines(net)

    out = [cat.stop_i[f"s{i}"] for i in range(city.STOPS)]
    assert lines[0]["stops"] == out
    assert lines[1]["stops"] == out[::-1]


def test_a_short_working_does_not_cut_the_line_short(net):
    ids, dist, sched = net.trip_stops["t1"]
    net.trip_stops["t1"] = (ids[:2], dist[:2], sched[:2])

    cat, lines = _lines(net)

    assert len(lines[0]["stops"]) == city.STOPS
