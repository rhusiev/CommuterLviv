"""The model's snapshot: saved, restored, and refused when it is not this
model's."""
import numpy as np
import pytest

from commuterlviv import config, layover, network, replay, snapshot

from . import city

AFTER = city.at(city.FLEET[-1][2] + 1800)    # once the last ride is done
HOLD_S = 12.0
ROAD_TOL = 0.02     # the timetable's prior is read per cell, so finer cells move it


@pytest.fixture
def learned(net, cfg, jammed_recording):
    """The model the jammed recording taught."""
    model, _ = replay.run(net, db=jammed_recording, cfg=cfg)
    return model


def _road(model):
    """Seconds the model gives the whole way out, as an epoch after the
    recording would see it."""
    model.refresh(AFTER)
    return model.time_between(city.SHAPE_OF["f0"], 0.0, np.array([city.LENGTH]))


def test_a_restored_model_times_the_road_as_the_one_saved(net, cfg, learned, tmp_path):
    path = tmp_path / "model.npz"
    snapshot.save(snapshot.export(learned, t=123.0), path)
    fresh = replay.build(net, cfg)

    assert snapshot.load(fresh, path) == 123.0
    assert _road(fresh) == pytest.approx(_road(learned))
    assert _road(fresh) != pytest.approx(_road(replay.build(net, cfg)))


def test_a_restored_model_keeps_the_turnarounds_and_stands(net, cfg, learned):
    learned.layovers.see((city.ROUTE, "s0"), False, 300.0)
    learned.layovers.restore_rows(np.ones((3, len(layover.FEATURES) + 1)))
    fresh = replay.build(net, cfg)

    snapshot.restore(fresh, snapshot.export(learned))

    assert fresh.layovers.seen == learned.layovers.seen
    assert np.array_equal(fresh.layovers.training(), learned.layovers.training())


def test_rows_are_restored_and_timed_when_no_shape_fits_any_more(net, cfg, learned):
    learned.layovers.restore_rows(np.ones((3, len(layover.FEATURES) + 1)))
    data = snapshot.export(learned, t=123.0)
    data["shapes"] = np.array([f"gone-{s}" for s in data["shapes"]])
    fresh = replay.build(net, cfg)

    assert snapshot.restore(fresh, data) == 123.0
    assert np.array_equal(fresh.layovers.training(), learned.layovers.training())
    # what was learned per cell stays behind; per corridor, it still applies
    assert np.array_equal(fresh.pace.cf.w, replay.build(net, cfg).pace.cf.w)
    assert not np.array_equal(fresh.pace.rf.w, replay.build(net, cfg).pace.rf.w)


def test_cells_of_another_length_are_restored_into_the_new_ones(net, cfg,
                                                                jammed_recording):
    coarse = network.regrid(net, network.Geometry(cell=2 * network.DEFAULT.cell))
    old, _ = replay.run(coarse, db=jammed_recording, cfg=cfg)
    fresh = replay.build(net, cfg)

    snapshot.restore(fresh, snapshot.export(old))

    assert _road(fresh) == pytest.approx(_road(old), rel=ROAD_TOL)
    assert _road(fresh) != pytest.approx(_road(replay.build(net, cfg)), rel=ROAD_TOL)


def test_finer_cells_share_the_standing_their_old_cell_learned(net, cfg):
    coarse = network.regrid(net, network.Geometry(cell=2 * network.DEFAULT.cell))
    old = replay.build(coarse, cfg)
    old.hold.cf.mean[:] = HOLD_S
    old.hold.cf.w[:] = 1.0
    fresh = replay.build(net, cfg)

    snapshot.restore(fresh, snapshot.export(old))

    for sid, base in fresh.shape_base.items():
        new = fresh.hold.cf.mean[base:base + net.shapes[sid].cells]
        assert new.sum() == pytest.approx(HOLD_S * coarse.shapes[sid].cells)


def test_another_variants_snapshot_is_not_restored(net, learned):
    other = replay.build(net, config.BY_NAME["full"])

    assert snapshot.restore(other, snapshot.export(learned)) is None


def test_a_missing_snapshot_is_no_snapshot(net, cfg, tmp_path):
    assert snapshot.load(replay.build(net, cfg), tmp_path / "model.npz") is None


def test_a_broken_snapshot_is_no_snapshot(net, cfg, tmp_path):
    path = tmp_path / "model.npz"
    path.write_bytes(b"not a snapshot")

    assert snapshot.load(replay.build(net, cfg), path) is None
