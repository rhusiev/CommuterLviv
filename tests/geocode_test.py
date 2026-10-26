"""The place search's clamp to the city, and its bias to the city's own places."""
import pytest

from commuterlviv import walk
from commuterlviv.live import geocode, wire

from .places_index import Place, write

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


def _numbered(name, street=None):
    """A Photon feature at the centre named only by a house number."""
    properties = {"name": name, "osm_value": "locality", "street": street,
                  "housenumber": name if street else None}
    return {"geometry": {"coordinates": geocode.CENTRE[::-1]}, "properties": properties}


def test_photon_s_places_named_only_by_a_house_number_are_left_out():
    assert geocode._place(_numbered("55")) is None


def test_photon_s_places_named_only_by_a_house_number_go_by_their_address():
    assert geocode._place(_numbered("55", "вулиця Шевченка"))["name"] == "вулиця Шевченка 55"


def _hit(name, km_east, kind=None):
    """A search row `km_east` km east of the city centre."""
    lat, lon = geocode.CENTRE
    return {"name": name, "where": "", "lat": lat,
            "lon": lon + km_east * 1000 / walk.metres(lat, 0, lat, 1), "kind": kind}


def _street(name, km_east, kind):
    return {**_hit(name, km_east, kind), geocode.STREET: True}


# a village inside the box, past the city's own streets, and a street in town
VILLAGE_KM = 12
TOWN_KM = 2


def _geocoder(monkeypatch, local, remote, nearby=()):
    """`local` as the index's places found by name, `nearby` as those found
    by their surroundings, `remote` as Photon's."""
    geocoder = geocode.Geocoder("https://photon.invalid")
    monkeypatch.setattr(geocoder, "_local", lambda q: (local, list(nearby)))
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
    monkeypatch.setattr(geocode.mapidx, "search", lambda path, q, limit, origin, within: [
        {"name": r["name"], "address": [], "lat": r["lat"], "lon": r["lon"], "named": True,
         "category": "amenity=school"}
        for r in rows])

    found = geocode.Geocoder("", index=index)._merge("shevchenka")

    assert found[0]["name"] == "Shevchenka school"


# where the index keeps a region's places past the city's box
OBLAST_KM = 60


def test_the_index_finds_the_city_s_place_behind_more_of_the_oblast_s_than_it_keeps(
        monkeypatch, tmp_path):
    monkeypatch.setattr(geocode, "WIDE", 1)
    # the index cuts its candidates to ten times what is asked for
    far = [_hit("Shevchenka", OBLAST_KM) for _ in range(10 * geocode.WIDE)]
    near = _hit("Shevchenka", TOWN_KM)
    index = write(tmp_path / "search.sqlite",
                  [Place(h["name"], h["lat"], h["lon"]) for h in [*far, near]])

    found, _ = geocode.Geocoder("", index=index)._local("shevchenka")

    assert [(h["lat"], h["lon"]) for h in found] == [(near["lat"], near["lon"])]


def test_the_index_s_places_named_only_by_a_house_number_are_left_out(tmp_path):
    names = ["7а", "12/2б", "55", "36,6", "№120", "22 Гектари"]
    index = write(tmp_path / "search.sqlite",
                  [Place(n, *geocode.CENTRE, context=("Шевченка",)) for n in names])

    _, found = geocode.Geocoder("", index=index)._local("шевченка")

    assert {h["name"] for h in found} == {"36,6", "№120", "22 Гектари"}


def test_the_index_tells_a_place_named_so_from_one_on_a_street_named_so(tmp_path):
    index = write(tmp_path / "search.sqlite", [
        Place("Urban Coffee", *geocode.CENTRE, context=("проспект Шевченка",)),
        Place("Школа імені Шевченка", *geocode.CENTRE),
    ])

    named, nearby = geocode.Geocoder("", index=index)._local("шевченка")

    assert [h["name"] for h in named] == ["Школа імені Шевченка"]
    assert [h["name"] for h in nearby] == ["Urban Coffee"]


def test_the_index_s_streets_lead_its_other_places_of_the_name(tmp_path):
    index = write(tmp_path / "search.sqlite", [
        Place("Зелена Сливка", *geocode.CENTRE),
        Place("ЖК Зелена околиця", *geocode.CENTRE, category="landuse=residential"),
        Place("Зелена вулиця", *geocode.CENTRE, category="highway=residential"),
    ])

    named, _ = geocode.Geocoder("", index=index)._local("зелена")

    # the estate's name sorts first in the index, so only the street's
    # highway=* puts the street before it
    assert [(h["name"], h["kind"]) for h in named][0] == ("Зелена вулиця", "residential")


def test_photon_s_street_is_left_out_where_the_index_has_a_street_of_its_name(
        monkeypatch):
    local = _street("Городоцька вулиця", VILLAGE_KM, "residential")
    stretches = [_street("Городоцька вулиця", km, "primary")
                 for km in (TOWN_KM, VILLAGE_KM / 2)]
    stop = _hit("Городоцька вулиця", TOWN_KM, "bus_stop")

    found = _geocoder(monkeypatch, [local], [*stretches, stop])._merge("городоцька")

    assert found == [stop, _hit("Городоцька вулиця", VILLAGE_KM, "residential")]


def test_photon_s_street_comes_before_the_index_s_places_only_on_it(monkeypatch):
    school, street = _hit("Shevchenka school", TOWN_KM), _hit("Shevchenka avenue", TOWN_KM)
    cafes = [_hit(f"Cafe {i}", TOWN_KM) for i in range(geocode.LIMIT)]

    found = _geocoder(monkeypatch, [school], [street], cafes)._merge("shevchenka avenue")

    assert found[:2] == [school, street]


# m between two stretches of one street in OSM, as Photon answers "проспект Шевченка"
STRETCH_M = 300


def _street_feature(lat, lon, district):
    return {"geometry": {"coordinates": [lon, lat]},
            "properties": {"name": "проспект Шевченка", "type": "street",
                           "osm_value": "primary", "district": district}}


def test_photon_s_street_is_listed_once_however_many_stretches_it_has(monkeypatch):
    lat, lon = geocode.CENTRE
    step = STRETCH_M / walk.metres(lat, lon, lat + 1, lon)
    features = [_street_feature(lat + i * step, lon, "Галицький") for i in range(3)] \
        + [_street_feature(lat, lon, "Сихівський")]
    geocoder = geocode.Geocoder("https://photon.invalid")
    monkeypatch.setattr(geocoder.session, "get", lambda url, timeout: _Answer(features))

    found = geocoder._ask("проспект шевченка")

    assert [h["where"] for h in found] == ["Галицький", "Сихівський"]


class _Answer:
    def __init__(self, features):
        self.features = features

    def raise_for_status(self):
        pass

    def json(self):
        return {"features": self.features}
