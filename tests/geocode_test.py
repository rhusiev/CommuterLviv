"""The place search's clamp to the city."""
import pytest

from commuterlviv import walk
from commuterlviv.live import geocode, wire

# how far a test point stands from an edge, well inside walk.MARGIN
STEP = walk.MARGIN / 2
MID_LAT = wire.LAT0 + wire.DLAT / 2
MID_LON = wire.LON0 + wire.DLON / 2

# (lat, lon, offered): the middle, then each side of the vehicle box just past
# it, where the footpaths still reach, and past the footpaths' reach
POINTS = [
    (MID_LAT, MID_LON, True),
    (wire.LAT0 - STEP, MID_LON, True),
    (wire.LAT0 - walk.MARGIN - STEP, MID_LON, False),
    (wire.LAT0 + wire.DLAT + STEP, MID_LON, True),
    (wire.LAT0 + wire.DLAT + walk.MARGIN + STEP, MID_LON, False),
    (MID_LAT, wire.LON0 - STEP, True),
    (MID_LAT, wire.LON0 - walk.MARGIN - STEP, False),
    (MID_LAT, wire.LON0 + wire.DLON + STEP, True),
    (MID_LAT, wire.LON0 + wire.DLON + walk.MARGIN + STEP, False),
]


def _feature(lat, lon):
    return {"geometry": {"coordinates": [lon, lat]},
            "properties": {"name": "Somewhere", "osm_value": "cafe"}}


@pytest.mark.parametrize(("lat", "lon", "offered"), POINTS)
def test_a_place_is_offered_as_far_as_the_footpaths_reach(lat, lon, offered):
    assert (geocode._place(_feature(lat, lon)) is not None) == offered
