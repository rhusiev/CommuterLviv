import pytest

from commuterlviv import config

from . import city, postgres


@pytest.fixture
def net(monkeypatch, tmp_path):
    """The made-up city's network, built from its own feed in a scratch data
    directory, so nothing reads or writes the real `data/`."""
    return city.install(monkeypatch, tmp_path / "data")


@pytest.fixture
def cfg():
    """The model variant the server runs."""
    return config.BY_NAME["profile"]


@pytest.fixture
def jammed_recording(tmp_path, net):
    """A recording of the fleet's rides out along a road jammed on its far half."""
    db = tmp_path / "feed.db"
    city.record(db, {f"v{k}": city.ride(trip, speed=city.jammed)
                     for k, (trip, *_) in enumerate(city.FLEET)})
    return db


@pytest.fixture(scope="session")
def database():
    """A Postgres for the service, shared by every test that needs one."""
    with postgres.server() as url:
        yield url
