"""The vehicle tracker: where a vehicle is along its trip, and when it passed
each stop."""
import dataclasses

import pytest

from commuterlviv import track

from . import city

PASS_TOL_S = 5.0
END_TOL_M = 10.0
STAND_S = 300.0
TURN_S = 10.0            # a turnaround far shorter than track.GAP_RESET
FROZEN = (12, 33)        # fixes 10 s apart, so 600 m to 1650 m along the trip
UNSEEN = (2, 3)          # the stops it passed meanwhile, at 1000 m and 1500 m


def _observe(net, fixes, trip, tr=None):
    tr = tr or track.Track(veh="v1")
    passed = {}
    for f in fixes:
        _, passings = track.observe(tr, net, f.ts, f.lat, f.lon, f.speed,
                                    f.odometer, trip)
        passed.update({i: t for i, t, _ in passings})
    return tr, passed


def test_passings_are_timed_where_the_vehicle_crossed_each_stop(net):
    start = city.at(city.DEPARTS["t1"])

    _, passed = _observe(net, city.drive("t1", start, every=15.0), "t1")

    assert sorted(passed) == list(range(1, city.STOPS))
    for i, t in passed.items():
        assert t == pytest.approx(start + i * city.LEG_S, abs=PASS_TOL_S)


def test_the_track_ends_at_the_far_stop_and_settles_standing(net):
    tr, _ = _observe(net, city.ride("t1", stand=STAND_S), "t1")

    assert tr.s == pytest.approx(net.trip_stops["t1"][1][-1], abs=END_TOL_M)
    assert tr.v < track.HOLD_SPEED


def test_a_long_silence_starts_a_new_run(net):
    fixes = city.ride("t1")
    tr, _ = _observe(net, fixes[:5], "t1")
    run = tr.run
    late = fixes[5]
    gap = track.GAP_RESET + 1.0

    track.observe(tr, net, late.ts + gap, late.lat, late.lon, late.speed,
                  late.odometer, "t1")

    assert tr.run == run + 1


def test_a_new_trip_starts_a_new_run(net):
    out = city.ride("t1")
    tr, _ = _observe(net, out, "t1")
    run = tr.run
    back = city.drive("t2", out[-1].ts + TURN_S)

    _, passed = _observe(net, back, "t2", tr)

    assert tr.trip == "t2" and tr.run == run + 1
    assert sorted(passed) == list(range(1, city.STOPS))


def test_fixes_that_froze_and_came_back_far_ahead_start_over_there(net):
    """As through an air raid alert: the place, the odometer and the speed stop
    changing while the fixes keep coming, then the place comes back where the
    vehicle really is and the odometer carries on from where it stopped."""
    start = city.at(city.DEPARTS["t1"])
    fixes = city.drive("t1", start)
    first, back = fixes[FROZEN[0]], fixes[FROZEN[1]]
    skipped = back.odometer - first.odometer
    frozen = [dataclasses.replace(first, ts=f.ts, speed=0.0)
              for f in fixes[FROZEN[0]:FROZEN[1]]]
    after = [dataclasses.replace(f, odometer=f.odometer - skipped)
             for f in fixes[FROZEN[1]:]]

    _, passed = _observe(net, fixes[:FROZEN[0]] + frozen + after, "t1")

    assert sorted(passed) == [i for i in range(1, city.STOPS) if i not in UNSEEN]
    for i, t in passed.items():
        assert t == pytest.approx(start + i * city.LEG_S, abs=PASS_TOL_S)
