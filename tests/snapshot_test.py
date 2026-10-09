"""The model's snapshot: saved, restored, and refused when it is not this
model's."""
import numpy as np
import pytest

from commuterlviv import config, layover, replay, snapshot

from . import city

AFTER = city.at(city.FLEET[-1][2] + 1800)    # once the last ride is done


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


def test_another_variants_snapshot_is_not_restored(net, learned):
    other = replay.build(net, config.BY_NAME["slow-day"])

    assert snapshot.restore(other, snapshot.export(learned)) is None


def test_a_missing_snapshot_is_no_snapshot(net, cfg, tmp_path):
    assert snapshot.load(replay.build(net, cfg), tmp_path / "model.npz") is None


def test_a_broken_snapshot_is_no_snapshot(net, cfg, tmp_path):
    path = tmp_path / "model.npz"
    path.write_bytes(b"not a snapshot")

    assert snapshot.load(replay.build(net, cfg), path) is None
