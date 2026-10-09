"""Footpaths for the made-up city: the road along the line and one side street,
`SIDE_M` long, running north from the middle stop to the door."""
import numpy as np

from commuterlviv import plan, walk as footpaths

from . import city

SIDE_M = 300.0
NODE_EVERY_M = 100.0
MIDDLE = city.STOPS // 2
M_PER_DEGREE_LAT = 111320.0
DOOR = (city.LAT + SIDE_M / M_PER_DEGREE_LAT, city._point(MIDDLE * city.GAP_M)[1])


def _overpass():
    """Overpass JSON for the road and the side street."""
    road = np.arange(0.0, city.LENGTH + NODE_EVERY_M / 2, NODE_EVERY_M)
    side = np.arange(NODE_EVERY_M, SIDE_M + NODE_EVERY_M / 2, NODE_EVERY_M)
    nodes = [(k + 1, *city._point(d)) for k, d in enumerate(road)]
    corner = int(np.flatnonzero(road == MIDDLE * city.GAP_M)[0]) + 1
    lat, lon = city._point(MIDDLE * city.GAP_M)
    north = [(len(nodes) + k + 1, lat + n / M_PER_DEGREE_LAT, lon)
             for k, n in enumerate(side)]
    return {"elements": [
        *({"type": "node", "id": i, "lat": a, "lon": o} for i, a, o in nodes + north),
        {"type": "way", "nodes": [i for i, *_ in nodes]},
        {"type": "way", "nodes": [corner, *(i for i, *_ in north)]},
    ]}


def load(net, tmp_path):
    """What `plan.load` reads for the city: its timetable, the footpaths and
    the transfers between its stops, built into `tmp_path`."""
    tt = plan.Timetable(net)
    walk = footpaths.Walk(*footpaths.compile_graph(_overpass()))
    path = plan.build_transfers(tt, walk, path=tmp_path / "transfers.npz")
    return tt, walk, plan.Transfers.load(path)
