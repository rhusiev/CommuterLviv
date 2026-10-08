"""The offline replay end to end: a recording in, predictions and truth out."""
import numpy as np
import pytest

from commuterlviv import replay

from . import city

NIGHT = 23 * 3600           # s past midnight, long after the last ride
TOO_LATE_S = 301.0          # past the replay's 300 s limit on polling delay

LEARNED = 4                 # fleet rides set off before the first one judged


def _errors(res, trips):
    """|predicted - true| per scored (prediction, stop) on these trips."""
    buf = res.buf.done()
    keep = np.isin(np.array(res.trip_ids)[buf["trip"]], trips)
    out = []
    for r in buf[keep]:
        truth = res.truth.get((r["veh"], r["trip"], r["run"], r["stop_i"]))
        if truth is not None:
            out.append(abs(res.t0 + r["eta"] - truth))
    return np.array(out)


def test_every_stop_crossed_is_recorded_as_truth(net, jammed_recording):
    _, res = replay.run(net, db=jammed_recording)

    crossed = {(res.trip_ids[ti], i) for _, ti, _, i in res.truth}
    for trip, *_ in city.FLEET:
        assert {i for t, i in crossed if t == trip} == set(range(1, city.STOPS))


def test_the_model_learns_where_the_road_is_slower_than_the_timetable(
        net, cfg, jammed_recording):
    _, res = replay.run(net, db=jammed_recording, cfg=cfg)
    first = [city.FLEET[0][0]]
    later = [trip for trip, *_ in city.FLEET[LEARNED:]]

    before, after = _errors(res, first), _errors(res, later)

    assert len(before) and len(after)
    assert after.mean() < before.mean() / 10


def test_a_window_with_no_fixes_says_why(net, jammed_recording):
    with pytest.raises(replay.NoData, match="no usable vehicle fixes"):
        replay.run(net, t_from=city.at(NIGHT), db=jammed_recording)


def test_fixes_polled_too_late_are_not_replayed(tmp_path, net):
    db = tmp_path / "feed.db"
    city.record(db, {"v1": city.ride("f0")}, delay=TOO_LATE_S)

    with pytest.raises(replay.NoData):
        replay.run(net, db=db)
