"""The live engine end to end: vehicle fixes in, the arrivals boards out."""
import numpy as np
import pytest

from commuterlviv import layover, replay
from commuterlviv.live import state

from . import city

ETA_TOL_S = 30.0
CAME_TOL_S = 15.0
STAND_S = 600.0


def _epoch_after(live, t):
    """The first epoch of the minute grid at or after `t`."""
    return np.ceil(t / live.epoch_s) * live.epoch_s


def _run(live, fixes, until):
    """Feed the fixes in order, stepping an epoch on the minute grid as the
    service does; the arrivals of every epoch, by when it ran."""
    boards = {}
    nxt = _epoch_after(live, fixes[0].ts)
    for f in fixes:
        while f.ts >= nxt:
            boards[nxt] = live.epoch(nxt)
            nxt += live.epoch_s
        live.fix("v1", f.ts, f.lat, f.lon, f.speed, f.odometer, f.trip)
    while nxt <= until:
        boards[nxt] = live.epoch(nxt)
        nxt += live.epoch_s
    return boards


@pytest.fixture
def live(net, cfg):
    return state.Live(net, cfg)


def _board(live, arrivals, stop):
    return arrivals.at(live.cat.stop_i[stop])


def test_a_vehicle_on_time_is_predicted_at_each_stop_ahead(live):
    start = city.at(city.DEPARTS["t1"])
    now = _epoch_after(live, start + 1.5 * city.LEG_S)

    arrivals = _run(live, city.ride("t1"), now)[now]

    for i in range(2, city.STOPS):
        rows = _board(live, arrivals, f"s{i}")
        live_rows = rows[rows["planned"] == 0]
        assert len(live_rows) == 1
        assert live_rows["t"][0] == pytest.approx(start + i * city.LEG_S, abs=ETA_TOL_S)


def test_the_vehicle_on_its_way_has_the_stops_ahead_in_their_order(live):
    now = _epoch_after(live, city.at(city.DEPARTS["t1"]) + 1.5 * city.LEG_S)

    arrivals = _run(live, city.ride("t1"), now)[now]
    ahead = arrivals.of(live.wire["v1"])

    on_board = ahead[ahead["planned"] == 0]
    assert on_board["stop"].tolist() == [live.cat.stop_i[f"s{i}"]
                                         for i in range(2, city.STOPS)]
    assert ahead["t"].min() >= now


def test_a_vehicle_in_early_runs_its_next_trip_from_the_timetable(live):
    start = city.at(city.DEPARTS["t1"])
    came = start + (city.STOPS - 1) * city.LEG_S
    now = _epoch_after(live, came + STAND_S / 2)
    t2 = city.at(city.DEPARTS["t2"])

    arrivals = _run(live, city.ride("t1", stand=STAND_S), now)[now]

    assert live.model.layovers.came("v1", "t1") == pytest.approx(came, abs=CAME_TOL_S)
    for seq in range(city.STOPS):
        rows = _board(live, arrivals, f"s{city.STOPS - 1 - seq}")
        planned = rows[rows["planned"] == 1]    # t2 first; s4 also ends t3
        assert planned["t"][0] == pytest.approx(t2 + seq * city.LEG_S, abs=ETA_TOL_S)


def test_the_chain_stops_at_the_horizon(live, monkeypatch):
    now = _epoch_after(live, city.at(city.DEPARTS["t1"]) + 1.5 * city.LEG_S)
    t3 = city.at(city.DEPARTS["t3"])
    # the horizon falls halfway along t3, the trip after next
    monkeypatch.setattr(replay, "HORIZON", t3 + 2.5 * city.LEG_S - now)

    arrivals = _run(live, city.ride("t1"), now)[now]

    assert arrivals.eta["t"].max() <= now + replay.HORIZON
    near, far = (_board(live, arrivals, s) for s in ("s1", f"s{city.STOPS - 1}"))
    assert near["planned"].sum() == 2       # t2 going back, t3 going out
    assert far["planned"].sum() == 1        # t2 leaving; t3 gets there too late


def test_a_stand_is_noted_for_the_departure_model_and_learned_from_on_leaving(live):
    t1, t2 = (city.at(city.DEPARTS[t]) for t in ("t1", "t2"))
    stand = t2 - (t1 + (city.STOPS - 1) * city.LEG_S)
    fixes = city.ride("t1", stand=stand) + city.ride("t2")

    _run(live, fixes, fixes[-1].ts)

    rows = live.model.layovers.training()
    in_for, left = rows[:, layover.FEATURES.index("in for")], rows[:, -1]
    assert len(rows) >= (stand - layover.TURN) // live.epoch_s - 1
    assert np.all(np.diff(in_for) > 0)
    assert np.all(left > 0)
    assert np.ptp(in_for + left) < 1.0    # each minute: in so long, so long to go


def test_positions_carry_the_vehicle_on_its_route(live):
    fixes = city.ride("t1")
    mid = fixes[len(fixes) // 2]
    _run(live, [f for f in fixes if f.ts <= mid.ts], mid.ts)

    pos = live.poll_done(mid.ts)

    assert len(pos.veh) == 1
    v = pos.veh[0]
    assert live.cat.routes[v["route"]] == city.ROUTE
    assert (v["lat"], v["lon"]) == pytest.approx((mid.lat, mid.lon), abs=1e-4)
    assert v["flags"] & state.MOVING
