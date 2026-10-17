"""The live service over the made-up city: its settings, and the outside world
it talks to replaced by the city's own feed or by nothing."""
import datetime
import time
import uuid

from commuterlviv import collect, localtime, replay
from commuterlviv.live import journeys, settings

from . import city

FAST_ARGON2 = {"time_cost": 1, "memory_cost": 8 * 1024, "parallelism": 1}
POLL_S = 0.5
EPOCH_S = 1.0
PASSWORD = "a long enough password"
# The city's timetable runs only in the morning. The service times a bus's next
# trips from their nearest timetabled start (`layover.clock`), which at night is
# tomorrow's, so it would plan no ride on the bus. Noon is chosen
NOON_S = 12 * 3600


def username(name):
    """`name`, made unique, since the database may outlive a run."""
    return f"{name}-{uuid.uuid4().hex[:8]}"


def settings_for(database, origin):
    """Settings for a service at `origin` that anyone may register with and
    change their password on, which polls and recomputes every `POLL_S` and
    `EPOCH_S`."""
    return settings.Settings(
        database_url=database, variant="profile", secure_cookies=False,
        origins=(origin,), web_base=origin, registration="open", password_change=True,
        session_idle=3600.0, session_max=86400.0, remember_days=1.0,
        trust_proxy=False, build_planner=False, self_tiles=False, photon_url="",
        places_url="", poll_veh=POLL_S, epoch=EPOCH_S, dev=False, argon2=FAST_ARGON2)


def _noon():
    """A fixed-offset zone in which it is noon now."""
    day = localtime.DAY_S
    offset = (NOON_S - time.time() % day) % day
    if offset > day / 2:
        offset -= day
    return datetime.timezone(datetime.timedelta(seconds=offset))


def isolate(monkeypatch, tmp_path):
    """Feed the service the city's bus, at noon whatever the hour, with no
    recording to warm up from and no journey planner; the feed, to know when the
    bus set off."""
    monkeypatch.setattr(localtime, "TZ", _noon())
    feed = city.Feed()
    monkeypatch.setattr(collect, "rt", feed)
    monkeypatch.setattr(replay, "DB", str(tmp_path / "no-recording.db"))
    monkeypatch.setattr(journeys.Planner, "maybe", classmethod(lambda *a: None))
    return feed
