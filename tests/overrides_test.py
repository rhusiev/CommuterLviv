"""`overrides.toml`'s rules, folded into the made-up city's network."""
import pytest

from commuterlviv import network, overrides

from . import city

OUT, BACK = "Stop 4", "Stop 0"   # the last stop's name, each way
MIDDLE = 2                       # the stop the rules move


@pytest.fixture
def rules(net, monkeypatch):
    """Builds the city again under the rules given, past `city.install`'s
    blanket of none; the network and the report it printed."""
    def build(capsys, add=(), remove=()):
        rules = overrides.Overrides(add, remove)
        monkeypatch.setattr(overrides.Overrides, "load",
                            classmethod(lambda cls: rules))
        built = network.build()
        return built, capsys.readouterr()
    return build


def _rule(toward=None):
    rule = {"route": "А1", "stop": str(100 + MIDDLE), "why": "a test"}
    return rule | ({"toward": toward} if toward else {})


def test_a_remove_rule_takes_the_stop_and_its_time_off_one_way(rules, capsys):
    net, out = rules(capsys, remove=[_rule(OUT)])

    stops, dist, sched = net.trip_stops["t1"]
    assert stops == ("s0", "s1", "s3", "s4")
    kept = (0, 1, 3, 4)
    assert dist == pytest.approx([k * city.GAP_M for k in kept], abs=1.0)
    assert sched == pytest.approx([city.DEPARTS["t1"] + k * city.LEG_S
                                   for k in kept])
    assert f"s{MIDDLE}" in net.trip_stops["t2"][0]
    assert "removed from 1 pattern(s)" in out.out


def test_a_remove_rule_without_toward_takes_the_stop_off_both_ways(rules, capsys):
    net, out = rules(capsys, remove=[_rule()])

    assert all(f"s{MIDDLE}" not in ids for ids, _, _ in net.trip_stops.values())
    assert "removed from 2 pattern(s)" in out.out


def test_a_remove_rule_the_feed_does_not_need_is_skipped_loudly(rules, capsys):
    net, out = rules(capsys, remove=[_rule("Nowhere")])

    assert all(f"s{MIDDLE}" in ids for ids, _, _ in net.trip_stops.values())
    assert "А1 at stop 102 matched nothing and was skipped" in out.err


def test_an_add_rule_puts_a_stop_back_between_its_neighbours(net):
    extra = overrides.Overrides(add=[_rule(OUT)])
    ids = ("s0", "s1", "s3", "s4")
    times = [0, 100, 300, 400]

    got, when = extra.patch(net, city.ROUTE, "out", ids, times)

    assert got == ("s0", "s1", "s2", "s3", "s4")
    assert when == [0, 100, 200, 300, 400]
    assert extra.applied == {0: 1}


def test_an_add_rule_leaves_the_way_back_alone(net):
    extra = overrides.Overrides(add=[_rule(OUT)])
    ids = ("s4", "s3", "s1", "s0")

    got, _ = extra.patch(net, city.ROUTE, "back", ids, [0, 100, 300, 400])

    assert got == ids
    assert extra.applied == {0: 0}


def test_a_stop_both_added_and_removed_stays_removed(net):
    extra = overrides.Overrides(add=[_rule(OUT)], remove=[_rule(OUT)])
    ids = ("s0", "s1", "s3", "s4")

    got, when = extra.patch(net, city.ROUTE, "out", ids, [0, 100, 300, 400])

    assert got == ids
    assert when == [0, 100, 300, 400]
