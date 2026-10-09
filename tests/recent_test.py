"""What the ETA correction is told of the last minutes: the city's recent miss,
a vehicle's own speed and the vehicles around it."""
import math
from types import SimpleNamespace

import numpy as np
import pytest

from commuterlviv import recent

MAX_GAP_S = 120.0
PACE_S_PER_M = 0.2
SPEED = 10.0
EPOCH_S = 60.0


def _between(shape_id, d0, d1):
    return (np.asarray(d1) - d0) * PACE_S_PER_M


def _track(trip="t1", shape="sh1", ts=0.0):
    return SimpleNamespace(trip=trip, run=1, shape_id=shape, ts=ts)


def _got(veh, tr, s_now, dt, i=0):
    dt = np.asarray(dt, dtype=float)
    return veh, tr, (i, s_now, dt, np.arange(len(dt)))


def _features(r, veh, tr, now, s_now):
    return dict(zip(recent.NAMES, r.features(veh, tr, now, s_now, _between)))


def test_a_vehicle_seen_for_the_first_time_knows_nothing_of_its_recent_past():
    r = recent.Recent(MAX_GAP_S)
    tr = _track()

    r.note(0.0, [_got("v1", tr, 0.0, [100.0])])

    f = _features(r, "v1", tr, 0.0, 0.0)
    assert all(math.isnan(f[n]) for n in recent.NAMES if n != "city misses")
    assert f["city misses"] == 0


def test_own_speed_and_pace_are_taken_over_the_last_minutes_of_the_run_only():
    r = recent.Recent(MAX_GAP_S)
    tr = _track()
    slow_until = recent.OWN_S
    epochs = int(2 * recent.OWN_S / EPOCH_S)
    for n in range(epochs + 1):
        now = n * EPOCH_S
        s_now = SPEED * (now - slow_until / 2 if now > slow_until else now / 2)
        r.note(now, [_got("v1", tr, s_now, [100.0])])

    f = _features(r, "v1", tr, now, s_now)

    assert f["own speed"] == pytest.approx(SPEED)
    assert f["own pace"] == pytest.approx(SPEED * PACE_S_PER_M)


def test_a_stop_passed_tells_how_far_its_first_forecast_was_off():
    r = recent.Recent(MAX_GAP_S)
    tr = _track()
    r.note(0.0, [_got("v1", tr, 0.0, [300.0, recent.AHEAD_S + 1]),
                 _got("v2", _track("t2"), 0.0, [200.0])])
    r.note(EPOCH_S, [_got("v1", tr, 0.0, [240.0, 800.0])])

    r.passed("v1", tr, 0, 400.0, 1.0)     # first told at 0 s, 300 s out
    r.passed("v1", tr, 1, 900.0, 1.0)     # first told at 60 s, 800 s out
    r.passed("v2", _track("t2"), 0, 100.0, MAX_GAP_S + 1)
    r.note(2 * EPOCH_S, [])

    f = _features(r, "v1", tr, 2 * EPOCH_S, 0.0)
    assert f["city misses"] == 2
    assert f["city miss"] == pytest.approx(np.median([np.log(400 / 300), np.log(840 / 800)]))


def test_the_recent_miss_forgets_stops_passed_long_ago():
    r = recent.Recent(MAX_GAP_S)
    tr = _track()
    r.note(0.0, [_got("v1", tr, 0.0, [300.0])])
    r.passed("v1", tr, 0, 300.0, 1.0)

    r.note(300.0 + recent.RECENT_S + 1, [])

    assert math.isnan(_features(r, "v1", tr, 300.0 + recent.RECENT_S + 1, 0.0)["city miss"])


def test_the_vehicles_ahead_and_behind_on_the_same_shape_are_measured():
    r = recent.Recent(MAX_GAP_S)
    mid, ahead = _track("t2", ts=50.0), _track("t3", ts=40.0)
    r.note(60.0, [_got("v1", _track("t1"), 100.0, [100.0]),
                  _got("v2", mid, 500.0, [100.0]),
                  _got("v3", ahead, 900.0, [100.0]),
                  _got("v5", _track("t5"), 1500.0, [100.0]),
                  _got("v6", _track("t6"), 20.0, [100.0]),
                  _got("v4", _track("t4", shape="sh2"), 700.0, [100.0])])

    f = _features(r, "v2", mid, 60.0, 500.0)

    assert (f["m to leader"], f["m to follower"]) == (400.0, 400.0)
    assert f["s to leader"] == pytest.approx(400.0 * PACE_S_PER_M)
    assert f["leader fix age"] == 20.0
