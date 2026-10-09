"""Learning from the recording what a fresh model lacks: the replay that keeps
nothing but what the model learns, and the service's backfill from it."""
import asyncio

import numpy as np
import pytest

from commuterlviv import replay, snapshot
from commuterlviv.live import service, state
from commuterlviv.live.service import Service

from . import city
from .service import EPOCH_S, settings_for

NIGHT = 23 * 3600           # s past midnight, long after the last ride
OWN = 7.0                   # marks the rows a model noted itself


def _learned(model):
    """What `model` learned, as its snapshot has it, less when it was taken."""
    return {k: v for k, v in snapshot.export(model).items() if k != "t"}


def _same(a, b):
    assert a.keys() == b.keys()
    for k in a:
        assert np.array_equal(a[k], b[k], equal_nan=a[k].dtype.kind == "f"), k


def _service(net):
    return Service(settings_for("postgresql://unused", "http://localhost"), net,
                   log=lambda *a: None, persist=False)


def _replayed(net, cfg, db):
    """A fresh model, replayed over `db` the way `backfill` replays it."""
    model = replay.build(net, cfg)
    replay.run(net, db=db, model=model, epoch=EPOCH_S, keep=False)
    return model


def test_a_replay_that_keeps_nothing_learns_the_same(net, cfg, jammed_recording):
    kept, res = replay.run(net, db=jammed_recording, cfg=cfg)

    alone, nothing = replay.run(net, db=jammed_recording, cfg=cfg, keep=False)

    assert len(res.buf.done()) and res.truth
    assert not len(nothing.buf.done()) and not nothing.truth and not nothing.pos
    _same(_learned(alone), _learned(kept))


def test_a_replay_notes_the_stands_at_the_terminus_as_the_live_model_does(
        net, cfg, tmp_path):
    t1, t2 = (city.at(city.DEPARTS[t]) for t in ("t1", "t2"))
    out = city.ride("t1", stand=t2 - (t1 + (city.STOPS - 1) * city.LEG_S))
    fixes = out + [f for f in city.ride("t2") if f.ts > out[-1].ts]
    db = tmp_path / "stand.db"
    city.record(db, {"v1": fixes})
    live = state.Live(net, cfg, epoch=EPOCH_S)
    nxt = np.ceil(fixes[0].ts / EPOCH_S) * EPOCH_S
    for f in fixes:
        while f.ts >= nxt:
            live.epoch(nxt)
            nxt += EPOCH_S
        live.fix("v1", f.ts, f.lat, f.lon, f.speed, f.odometer, f.trip)

    model = _replayed(net, cfg, db)

    stands = live.model.layovers.training()
    assert len(stands)
    assert model.layovers.training() == pytest.approx(stands, nan_ok=True)


@pytest.fixture
def no_warmup(monkeypatch):
    monkeypatch.setattr(service, "BACKFILL_WARMUP_S", 0.0)


def test_a_cold_model_takes_everything_the_recording_teaches(
        net, cfg, jammed_recording, no_warmup):
    svc = _service(net)
    cold = _learned(svc.live.model)

    asyncio.run(svc.backfill(cold=True, db=jammed_recording, t_to=city.at(NIGHT)))

    got = _learned(svc.live.model)
    _same(got, _learned(_replayed(net, cfg, jammed_recording)))
    assert len(got[snapshot.PASSED])
    assert any(not np.array_equal(got[k], cold[k]) for k in got if k.endswith(".mean"))
    assert svc.refit.is_set()


def test_a_warm_model_takes_only_the_rows_and_keeps_its_own_as_newest(
        net, cfg, jammed_recording, no_warmup):
    svc = _service(net)
    model = svc.live.model
    boost, stands = model.boost.training(), model.layovers.training()
    model.boost.restore_rows(np.full((1, boost.shape[1]), OWN), model.boost.routes)
    model.layovers.restore_rows(np.full((1, stands.shape[1]), OWN))
    before = _learned(model)

    asyncio.run(svc.backfill(cold=False, db=jammed_recording, t_to=city.at(NIGHT)))

    got = _learned(model)
    replayed = _learned(_replayed(net, cfg, jammed_recording))
    for rows in (snapshot.PASSED, snapshot.STANDS):
        _same({rows: got[rows]},
              {rows: np.concatenate([replayed[rows], before[rows]])})
    _same({k: v for k, v in got.items() if k not in (snapshot.PASSED, snapshot.STANDS)},
          {k: v for k, v in before.items() if k not in (snapshot.PASSED, snapshot.STANDS)})
