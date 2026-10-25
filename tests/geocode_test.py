"""The place search's clamp to the city, and its bias to the city's own places."""
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


def _hit(name, km_east):
    """A search row `km_east` km east of the city centre."""
    lat, lon = geocode.CENTRE
    return {"name": name, "where": "", "lat": lat,
            "lon": lon + km_east * 1000 / walk.metres(lat, 0, lat, 1), "kind": None}


# a village inside the box, past the city's own streets, and a street in town
VILLAGE_KM = 12
TOWN_KM = 2


def _geocoder(monkeypatch, local, remote):
    geocoder = geocode.Geocoder("https://photon.invalid")
    monkeypatch.setattr(geocoder, "_local", lambda q: local)
    monkeypatch.setattr(geocoder, "_ask", lambda q: remote)
    return geocoder


def test_a_place_in_the_city_leads_the_villages_of_the_same_name(monkeypatch):
    villages = [_hit(f"Shevchenka {i}", VILLAGE_KM) for i in range(geocode.LIMIT)]
    town = _hit("Shevchenka avenue", TOWN_KM)

    found = _geocoder(monkeypatch, villages, [town])._merge("shevchenka")

    assert found[0] == town
    assert found[1:] == villages[:geocode.LIMIT - 1]


def test_the_index_still_leads_photon_inside_the_city(monkeypatch):
    local, remote = _hit("Rynok square", TOWN_KM), _hit("Rynok", TOWN_KM)

    assert _geocoder(monkeypatch, [local], [remote])._merge("rynok") == [local, remote]


def test_a_place_in_the_city_the_index_ranks_late_still_leads(monkeypatch, tmp_path):
    index = tmp_path / "search.sqlite"
    index.touch()
    rows = [_hit(f"Shevchenka {i}", VILLAGE_KM) for i in range(geocode.LIMIT)] \
        + [_hit("Shevchenka school", TOWN_KM)]
    monkeypatch.setattr(geocode.mapidx, "search", lambda path, q, limit, origin: [
        {"name": r["name"], "address": [], "lat": r["lat"], "lon": r["lon"]} for r in rows])

    found = geocode.Geocoder("", index=index)._merge("shevchenka")

    assert found[0]["name"] == "Shevchenka school"
