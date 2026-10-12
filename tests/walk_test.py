"""Where points and stops step onto the footpaths, and when a graph is due to be
fetched again.

The footpaths here are a street's two pavements, `GAP_M` apart, joined only
where they end. A stop's pole stands just off the north one, halfway along it,
where the nearest node is a corner of the south one."""
import math
import time

import numpy as np
import pytest

from commuterlviv import plan, walk as footpaths

from . import streets

LAT, LON = 49.84, 24.00
M_PER_DEGREE_LON = streets.M_PER_DEGREE_LAT * math.cos(math.radians(LAT))
LENGTH_M = 100.0     # of each pavement, west to east
GAP_M = 20.0         # between the pavements
POLE_M = 2.0         # from the pole to the north pavement
CAP_S = 600.0
# s to walk a few metres: anything more is a detour round the street
NEAR_S = 10.0
# s since a graph just saved was fetched, at most
JUST_S = 60.0


def _at(east_m, north_m):
    return (LAT + north_m / streets.M_PER_DEGREE_LAT,
            LON + east_m / M_PER_DEGREE_LON)


def _overpass():
    """The pavements: the south one has a node right across from the pole, the
    north one only its ends."""
    nodes = {1: _at(0, GAP_M), 2: _at(LENGTH_M, GAP_M),
             3: _at(0, 0), 4: _at(LENGTH_M / 2, 0), 5: _at(LENGTH_M, 0)}
    return {"elements": [
        *({"type": "node", "id": i, "lat": a, "lon": o}
          for i, (a, o) in nodes.items()),
        {"type": "way", "nodes": [1, 2]},
        {"type": "way", "nodes": [3, 4, 5]},
        {"type": "way", "nodes": [1, 3]},
        {"type": "way", "nodes": [2, 5]},
    ]}


@pytest.fixture
def walk():
    return footpaths.Walk(*footpaths.compile_graph(_overpass()))


POLE = _at(LENGTH_M / 2, GAP_M - POLE_M)


def _from(walk, lat, lon, stands):
    """Seconds from a point to each of `stands`, as the planner reads them."""
    here = walk.attach(lat, lon)
    return stands.read(walk.reach(here.ends(), CAP_S), here)


def test_the_pole_is_nearer_the_far_pavements_node_than_its_own(walk):
    # what the stops below are placed against: a stop placed on its nearest
    # node would board from the south pavement
    nearest = walk.near(*POLE)[0][1]

    assert (walk.lat[nearest], walk.lon[nearest]) == \
        pytest.approx(_at(LENGTH_M / 2, 0))


def test_somebody_at_the_pole_boards_there_rather_than_across_the_street(walk):
    stands = walk.stands(*np.array([POLE]).T)

    got = _from(walk, *_at(LENGTH_M / 2 + 1, GAP_M + 1), stands)

    assert got[0] < NEAR_S


def test_a_stop_is_reached_along_the_edge_it_shares_with_the_walker(walk):
    stands = walk.stands(*np.array([POLE]).T)
    east = 10.0

    got = _from(walk, *_at(LENGTH_M / 2 + east, GAP_M), stands)

    # past the pole, not out to a corner of the street and back
    assert got[0] == pytest.approx(walk.flat(east + POLE_M), abs=1.0)


def test_a_stop_away_from_every_footpath_is_out_of_reach(walk):
    far = _at(0, 10_000.0)

    stands = walk.stands(*np.array([POLE, far]).T)

    assert stands.spot(1) is None
    assert math.isinf(_from(walk, *POLE, stands)[1])


def test_a_slower_walker_takes_as_much_longer_to_a_stop(walk):
    stands = walk.stands(*np.array([POLE]).T)
    seen = walk.reach(walk.attach(*_at(0, GAP_M)).ends(), CAP_S)
    pace = 1.5

    slower = stands.paced(pace).read(seen * pace)

    assert slower[0] == pytest.approx(stands.read(seen)[0] * pace)


def test_transfers_saved_with_stops_on_nodes_are_rebuilt(net, tmp_path):
    tt, walk, _ = streets.load(net, tmp_path)
    old = tmp_path / "old.npz"
    np.savez(old, node=np.zeros(len(tt.stops), dtype=np.int64),
             to=np.zeros(0, dtype=np.int32), cost=np.zeros(0, dtype=np.float32),
             start=np.zeros(len(tt.stops) + 1, dtype=np.int64),
             model=np.array(walk.model), graph=np.array(walk.graph))

    assert plan.Transfers.load(old).stale(tt, walk)
    assert not plan.Transfers.load(tmp_path / "transfers.npz").stale(tt, walk)


@pytest.mark.parametrize("selector", footpaths.PLATFORMS)
def test_platforms_are_fetched_whatever_else_they_are_tagged(selector):
    assert f'way{selector}["foot"!="no"]' in footpaths.query((0, 0, 1, 1))


def test_a_graph_fetched_as_the_ways_asked_for_now_is_not_due(tmp_path):
    path = footpaths.save(tmp_path / "walk.npz", _overpass())

    assert footpaths.age(path) < JUST_S


@pytest.mark.parametrize("kind", [None, "another"])
def test_a_graph_fetched_as_other_ways_is_due_at_once(tmp_path, kind):
    path = tmp_path / "walk.npz"
    noted = {} if kind is None else {"kind": np.array(kind)}
    np.savez(path, built=np.array([time.time()]), **noted)

    assert footpaths.age(path) == math.inf
