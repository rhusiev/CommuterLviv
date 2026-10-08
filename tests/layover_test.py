"""The layover rule and its learned model: when a vehicle standing at the
first stop of its next trip will leave."""
import datetime

import numpy as np
import pytest

from commuterlviv import layover, model

from . import city

SCHED = city.at(city.DEPARTS["t2"])
READY = SCHED - 1200.0      # in and turned round, twenty minutes early
NOW = SCHED - 1000.0
AHEAD_S = 300.0
RING_ROWS = 4


@pytest.fixture
def lay(net):
    return layover.Layovers(net, model.TZ)


def _key(net):
    return net.trip_route["t2"], net.trip_stops["t2"][0][0]


def _seen(lay, net, waited, n=layover.NEED):
    for _ in range(n):
        lay.see(_key(net), waited, AHEAD_S)


def test_a_route_that_leaves_early_is_timed_ahead_of_its_timetable(lay, net):
    _seen(lay, net, waited=False)

    leave = lay.leave("t2", SCHED, ready=READY, now=NOW)

    assert leave == pytest.approx(SCHED - AHEAD_S)


def test_a_route_that_keeps_its_timetable_is_timed_by_it(lay, net):
    _seen(lay, net, waited=True)

    assert lay.leave("t2", SCHED, ready=READY, now=NOW) == SCHED


def test_too_few_turnarounds_leave_it_to_the_timetable(lay, net):
    _seen(lay, net, waited=False, n=layover.NEED - 1)

    assert lay.leave("t2", SCHED, ready=READY, now=NOW) == SCHED


def test_a_vehicle_in_late_leaves_after_its_turnaround(lay, net):
    _seen(lay, net, waited=False)
    ready = SCHED - 30

    assert lay.leave("t2", SCHED, ready=ready, now=ready) == ready + layover.TURN


def test_departures_already_gone_by_now_are_not_believed(lay, net):
    _seen(lay, net, waited=False)
    now = SCHED - AHEAD_S + 60    # every early one had left by now

    leave = lay.leave("t2", SCHED, ready=READY, now=now)

    assert leave == pytest.approx((SCHED + now) / 2)


def test_turnarounds_survive_export_and_restore(lay, net):
    _seen(lay, net, waited=False)
    lay.see(_key(net), True, 10.0)
    again = layover.Layovers(net, model.TZ)

    again.restore(**lay.export())

    assert again.seen == lay.seen


@pytest.mark.parametrize("n", [RING_ROWS - 1, RING_ROWS, RING_ROWS + 2])
def test_the_ring_keeps_the_newest_rows_oldest_first(monkeypatch, net, n):
    monkeypatch.setattr(layover, "ROWS", RING_ROWS)
    lay = layover.Layovers(net, model.TZ)
    width = len(layover.FEATURES) + 1

    for k in range(n):
        lay._add(np.full(width, k))

    assert lay.training()[:, 0].tolist() == list(range(max(0, n - RING_ROWS), n))


def test_rows_survive_training_and_restore(lay, net):
    rows = np.arange(30 * (len(layover.FEATURES) + 1), dtype=np.float32).reshape(30, -1)
    lay.restore_rows(rows)
    again = layover.Layovers(net, model.TZ)

    again.restore_rows(lay.training())

    assert np.array_equal(again.training(), rows)


def test_rows_of_another_version_are_ignored(lay):
    lay.restore_rows(np.zeros((5, len(layover.FEATURES))))

    assert len(lay.training()) == 0


def test_fit_learns_the_time_left_and_waits_for_enough_rows(monkeypatch):
    monkeypatch.setattr(layover, "NEED_ROWS", 500)
    rng = np.random.default_rng(1)
    x = rng.uniform(0, 1800, (600, len(layover.FEATURES)))
    rows = np.column_stack([x, 0.5 * x[:, 1]])

    assert layover.fit(rows[:layover.NEED_ROWS - 1]) is None
    fitted = layover.fit(rows)
    assert np.abs(fitted.predict(x) - rows[:, -1]).mean() < 60.0


def test_a_stand_is_timed_by_the_model_once_there_is_one(lay, net):
    class Fixed:
        def predict(self, x):
            return np.full(len(x), 600.0)
    lay.model = Fixed()

    lay.stand("t2", SCHED, ready=READY, now=NOW)
    lay.foretell(NOW)

    assert lay.leave("t2", SCHED, ready=READY, now=NOW) == NOW + 600.0


def test_the_minutes_of_a_stand_are_learned_from_once_it_leaves(lay, net):
    for now in (READY + 300, READY + 360):
        lay.stand("t2", SCHED, READY, now)
    dep = READY + 600

    lay.left(_key(net), "t2", dep, SCHED, early=True)

    assert lay.training()[:, -1].tolist() == [300.0, 240.0]
    assert lay.seen[_key(net)][-1] == (False, SCHED - dep)


def test_a_timetable_time_past_midnight_lands_on_the_service_day():
    after_midnight = datetime.datetime(2026, 10, 6, 0, 20, tzinfo=model.TZ).timestamp()
    sched = 24 * 3600 + 30 * 60      # 24:30 of the day before

    assert layover.clock(sched, after_midnight, model.TZ) == after_midnight + 600
