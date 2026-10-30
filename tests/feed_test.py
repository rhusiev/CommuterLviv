"""When the static feed is fetched again: only on purpose, never on a read."""
import os
import time

import requests

from commuterlviv import gtfs, network
from commuterlviv.live import refresh


def _age(days):
    then = time.time() - days * gtfs.MAX_AGE
    os.utime(gtfs.ZIP, (then, then))


def _unreachable(monkeypatch):
    """`requests.get` failing as an unreachable server does; the asks it got."""
    asked = []

    def get(*args, **kwargs):
        asked.append(args)
        raise requests.ConnectionError("unreachable")

    monkeypatch.setattr(gtfs.requests, "get", get)
    return asked


def test_a_stale_feed_is_read_as_held_without_fetching(net, monkeypatch):
    _age(2)
    asked = _unreachable(monkeypatch)

    rebuilt = network.load(rebuild=True)

    assert asked == []
    assert rebuilt.trip_stops.keys() == net.trip_stops.keys()


def test_the_start_fetches_a_stale_feed_and_serves_the_held_one_if_it_fails(
        net, monkeypatch):
    _age(2)
    held = gtfs.ZIP.read_bytes()
    asked = _unreachable(monkeypatch)
    said = []

    refresh.feed_at_start(lambda *parts: said.append(parts))

    assert len(asked) == 1
    assert gtfs.ZIP.read_bytes() == held
    assert said and said[0][0] == "start: keeping the feed held -"


def test_the_start_leaves_a_fresh_feed_alone(net, monkeypatch):
    asked = _unreachable(monkeypatch)

    refresh.feed_at_start(lambda *parts: None)

    assert asked == []
