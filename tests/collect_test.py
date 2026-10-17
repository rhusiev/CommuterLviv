import queue
import threading

import pytest

from commuterlviv import collect


@pytest.fixture
def loop(monkeypatch):
    """The collector's queue and stop flag, fresh and its own."""
    monkeypatch.setattr(collect, "writes", queue.Queue())
    monkeypatch.setattr(collect, "stop_flag", threading.Event())
    monkeypatch.setattr(collect, "stats", collect.collections.Counter())
    return collect.writes


def _once_then_stop(outcome):
    def once():
        collect.stop_flag.set()
        if isinstance(outcome, Exception):
            raise outcome
        return outcome
    return once


def test_a_poll_is_recorded_with_its_rows_and_header(loop):
    collect.poll_loop("veh", 1.0, _once_then_stop((3, 7)))

    kind, (t0, feed, header, n, took_ms, err) = loop.get_nowait()
    assert (kind, feed, header, n, err) == ("poll", "veh", 7, 3, None)
    assert took_ms >= 0
    assert collect.stats == {"veh_rows": 3, "veh_polls": 1}


def test_a_failed_poll_is_recorded_with_its_error(loop):
    collect.poll_loop("veh", 1.0, _once_then_stop(ValueError("feed down")))

    kind, (t0, feed, header, n, took_ms, err) = loop.get_nowait()
    assert (kind, feed, header, n) == ("poll", "veh", 0, 0)
    assert "feed down" in err
    assert collect.stats == {"veh_errors": 1}
