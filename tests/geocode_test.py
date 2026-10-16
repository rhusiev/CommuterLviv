"""The place search's clamp to the city."""
import numpy as np
import pytest

from commuterlviv.live import geocode, state, wire

# (lat, lon) inside the city, and just past each side of the box
POINTS = [(49.84, 24.03), (49.69, 24.03), (50.01, 24.03), (49.84, 23.84),
          (49.84, 24.31)]


def _feature(lat, lon):
    return {"geometry": {"coordinates": [lon, lat]},
            "properties": {"name": "Somewhere", "osm_value": "cafe"}}


@pytest.mark.parametrize(("lat", "lon"), POINTS)
def test_a_place_is_offered_only_where_the_map_can_show_a_vehicle(lat, lon):
    veh = np.zeros(1, state.VEH)
    veh["lat"], veh["lon"] = lat, lon

    offered = geocode._place(_feature(lat, lon)) is not None

    assert offered == bool(len(wire.inbox(veh)))
