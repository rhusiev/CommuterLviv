"""What the feed says of a vehicle itself, and an arrival doubted because its
vehicle stands still or has gone quiet."""
from commuterlviv.live import hub, state

from . import city

STAND_STEP_S = 5
# Past `state.STUCK_S`, with polls on the way so the standing is seen
STAND_S = state.STUCK_S + 60


def _at(live, fix, label=None, plate=None, ts=None):
    """`fix` again, at `ts`, with the feed's word on the vehicle."""
    ts = fix.ts if ts is None else ts
    live.fix("v1", ts, fix.lat, fix.lon, 0.0, fix.odometer, fix.trip,
             label, plate)
    return live.poll_done(ts)


def _ridden_to(live, i):
    """Vehicle "v1" ridden to its `i`-th fix of trip "t1"; that fix."""
    fixes = city.ride("t1")
    city.run(live, fixes[:i + 1], fixes[i].ts)
    return fixes[i]


def _stood(live, fix):
    """`fix`'s vehicle standing where `fix` is for `STAND_S`; the positions
    last published."""
    pos = None
    for dt in range(0, int(STAND_S) + 1, STAND_STEP_S):
        pos = _at(live, fix, ts=fix.ts + dt)
    return pos


def test_a_low_floor_vehicle_is_flagged_with_its_fleet_number(live):
    mid = _ridden_to(live, len(city.ride("t1")) // 2)

    pos = _at(live, mid, label="low_floor", plate=" 1054 ")
    seen = live.vehicle(int(pos.veh[0]["id"]))

    board = hub.due(live.epoch(mid.ts), range(len(live.cat.stops)), pos)

    assert pos.veh[0]["flags"] & state.LOW_FLOOR
    assert seen == {"fleet": "1054", "low_floor": True, "seen": round(mid.ts)}
    rows = [r for rs in board["stops"].values() for r in rs]
    assert rows and all(r["low_floor"] for r in rows)


def test_a_vehicle_the_feed_calls_high_floor_or_nothing_is_not_flagged(live):
    mid = _ridden_to(live, len(city.ride("t1")) // 2)

    assert not _at(live, mid, label="high_floor").veh[0]["flags"] & state.LOW_FLOOR
    assert live.vehicle(int(live.positions.veh[0]["id"]))["low_floor"] is False


def test_standing_still_mid_route_doubts_its_arrivals(live):
    mid = _ridden_to(live, len(city.ride("t1")) // 2)

    pos = _stood(live, mid)
    board = hub.due(live.epoch(mid.ts + STAND_S), range(len(live.cat.stops)), pos)

    assert pos.veh[0]["flags"] & state.STUCK
    rows = [r for rs in board["stops"].values() for r in rs]
    assert rows and all(r["doubt"] == "stuck" for r in rows)


def test_standing_at_the_end_of_the_line_is_laying_over_not_stuck(live):
    first = _ridden_to(live, 0)

    assert not _stood(live, first).veh[0]["flags"] & state.STUCK


def test_an_arrival_on_a_vehicle_that_went_quiet_is_doubted(live):
    mid = _ridden_to(live, len(city.ride("t1")) // 2)
    later = mid.ts + state.FRESH + 1

    pos = live.poll_done(later)
    board = hub.due(live.epoch(later), range(len(live.cat.stops)), pos)

    rows = [r for rs in board["stops"].values() for r in rs]
    assert rows and all(r["doubt"] == "silent" for r in rows)
