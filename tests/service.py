"""The live service over the made-up city: its settings, and the outside world
it talks to replaced by the city's own feed or by nothing."""
import uuid

from commuterlviv import collect, replay
from commuterlviv.live import journeys, settings

from . import city

FAST_ARGON2 = {"time_cost": 1, "memory_cost": 8 * 1024, "parallelism": 1}
POLL_S = 0.5
EPOCH_S = 1.0
PASSWORD = "a long enough password"


def username(name):
    """`name`, made unique, since the database may outlive a run."""
    return f"{name}-{uuid.uuid4().hex[:8]}"


def settings_for(database, origin):
    """Settings for a service at `origin` that anyone may register with, which
    polls and recomputes every `POLL_S` and `EPOCH_S`."""
    return settings.Settings(
        database_url=database, variant="profile", secure_cookies=False,
        origins=(origin,), web_base=origin, registration="open",
        session_idle=3600.0, session_max=86400.0, remember_days=1.0,
        trust_proxy=False, build_planner=False, self_tiles=False, photon_url="",
        places_url="", poll_veh=POLL_S, epoch=EPOCH_S, dev=False, argon2=FAST_ARGON2)


def isolate(monkeypatch, tmp_path):
    """Feed the service the city's bus, with no recording to warm up from and
    no journey planner; the feed, to know when the bus set off."""
    feed = city.Feed()
    monkeypatch.setattr(collect, "rt", feed)
    monkeypatch.setattr(replay, "DB", str(tmp_path / "no-recording.db"))
    monkeypatch.setattr(journeys.Planner, "maybe", classmethod(lambda *a: None))
    return feed
