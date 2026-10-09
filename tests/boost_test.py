"""The learned ETA correction: what it learns from, what it changes, and when
the service refits it."""
import asyncio

import numpy as np
import pytest

from commuterlviv import boost, layover, snapshot
from commuterlviv.live import state
from commuterlviv.live.service import Service

from . import city
from .service import settings_for

TO_GO_TOL_S = 15.0
WAIT_S = 10.0
FIT_TOL_S = 5.0


class _Shift:
    """A fitted model that has every ETA out by the same seconds."""

    def __init__(self, s):
        self.s = s

    def predict(self, x):
        return np.full(len(x), self.s)


@pytest.fixture
def live(net, cfg):
    return state.Live(net, cfg)


def _ride(live, until):
    """Ride `t1` through `live`, an epoch each minute; the arrivals at `until`."""
    nxt = np.ceil(city.at(city.DEPARTS["t1"]) / live.epoch_s) * live.epoch_s
    for f in city.ride("t1"):
        while f.ts >= nxt and nxt <= until:
            live.epoch(nxt)
            nxt += live.epoch_s
        if f.ts > until:
            break
        live.fix("v1", f.ts, f.lat, f.lon, f.speed, f.odometer, f.trip)
    return live.epoch(until)


def _due(live, arrivals, i):
    rows = arrivals.at(live.cat.stop_i[f"s{i}"])
    return rows["t"][rows["planned"] == 0][0]


def test_a_stop_passed_teaches_how_far_out_the_model_was(live, monkeypatch):
    monkeypatch.setattr(boost, "KEEP", 1.0)
    monkeypatch.setattr(boost, "SAMPLE_S", live.epoch_s)

    _ride(live, city.at(city.DEPARTS["t1"]) + city.STOPS * city.LEG_S)

    rows = live.model.boost.training()
    assert len(rows) > city.STOPS
    to_go = rows[:, -1] + rows[:, boost.FEATURES.index("model s")]
    went = rows[:, boost.FEATURES.index("m to go")] / city.SPEED
    assert to_go == pytest.approx(went, abs=TO_GO_TOL_S)


@pytest.mark.parametrize("shift", [120.0, -200.0])
def test_the_correction_is_faded_in_past_the_next_stops_and_keeps_their_order(net, cfg, shift):
    now = city.at(city.DEPARTS["t1"]) + 1.5 * city.LEG_S
    plain = state.Live(net, cfg)
    raw = _ride(plain, now)
    fixed = state.Live(net, cfg)
    fixed.model.boost.model = _Shift(shift)

    got = _ride(fixed, now)

    before = [_due(plain, raw, i) - now for i in range(2, city.STOPS)]
    after = [_due(fixed, got, i) - now for i in range(2, city.STOPS)]
    weight = np.clip((np.array(before) - boost.FADE_FROM_S) / boost.FADE_S, 0, 1)
    fixed = np.array(before) + weight * shift
    fixed -= weight * boost.EARLIER * np.maximum(fixed, 0)
    want = np.maximum.accumulate(np.maximum(fixed, 0))
    assert after == pytest.approx(want, abs=1)
    assert before[0] < boost.FADE_FROM_S and after[0] == before[0]


def test_a_passing_timed_across_a_long_gap_teaches_nothing(net):
    b = boost.Boost(net, city.DAY.tzinfo)
    tr = type("T", (), {"trip": "t1", "run": 1})()
    b._asked[("v1", "t1", 1, 2)] = [(0.0, np.zeros(len(boost.FEATURES)))]

    b.passed("v1", tr, 2, 100.0, boost.MAX_GAP_S + 1)
    b.passed("v1", tr, 2, 100.0, 1.0)

    assert len(b.training()) == 0


def test_a_fit_needs_enough_rows_and_then_learns_the_miss(monkeypatch):
    rng = np.random.default_rng(0)
    rows = np.column_stack([rng.random((2000, len(boost.FEATURES))), np.full(2000, 30.0)])
    rows[:, boost.FEATURES.index("route")] = 0
    rows[:, boost.FEATURES.index("type")] = 0
    monkeypatch.setattr(boost, "NEED_ROWS", len(rows) + 1)
    assert boost.fit(rows) is None
    monkeypatch.setattr(boost, "NEED_ROWS", len(rows))

    model = boost.fit(rows)

    assert model.predict(rows[:3, :-1]) == pytest.approx([30.0] * 3, abs=FIT_TOL_S)


def test_a_restored_model_keeps_the_passed_stops(net, cfg):
    learned = state.Live(net, cfg).model
    learned.boost.restore_rows(np.zeros((3, len(boost.FEATURES) + 1)), [city.ROUTE])
    fresh = state.Live(net, cfg).model

    snapshot.restore(fresh, snapshot.export(learned))

    assert np.array_equal(fresh.boost.training(), learned.boost.training())


def test_rows_from_another_feed_keep_their_routes_and_forget_dropped_ones(net):
    b = boost.Boost(net, city.DAY.tzinfo)
    rows = np.zeros((3, len(boost.FEATURES) + 1))
    col = boost.FEATURES.index("route")
    rows[:, col] = [0, 1, np.nan]

    b.restore_rows(rows, ["gone", city.ROUTE])

    got = b.training()[:, col]
    assert np.isnan(got[0]) and got[1] == b.routes.index(city.ROUTE) and np.isnan(got[2])


async def _until(done):
    async with asyncio.timeout(WAIT_S):
        while not done():
            await asyncio.sleep(0.01)


def test_a_refit_asked_for_fits_both_models_again(net, monkeypatch):
    fits = []
    monkeypatch.setattr(layover, "fit", lambda rows: fits.append("layover"))
    monkeypatch.setattr(boost, "fit", lambda rows: fits.append("boost"))
    svc = Service(settings_for("postgresql://unused", "http://localhost"), net,
                  log=lambda *a: None, persist=False)

    async def go():
        task = asyncio.create_task(svc.fit_loop())
        await _until(lambda: len(fits) == 2)
        svc.refit.set()
        await _until(lambda: len(fits) == 4)
        task.cancel()

    asyncio.run(go())

    assert fits == ["layover", "boost"] * 2
