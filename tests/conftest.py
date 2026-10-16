import pytest

from commuterlviv import config
from commuterlviv.live import journeys, state

from . import city, postgres, streets


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
def live(net, cfg):
    """A live engine over the city, as the server runs it."""
    return state.Live(net, cfg)


@pytest.fixture
def planner(net, tmp_path):
    """The journey planner over the city and its footpaths."""
    return journeys.Planner(*streets.load(net, tmp_path), state.Catalog(net))


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
