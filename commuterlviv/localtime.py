"""The city's clock: the zone its timetables run in, and where its days start.

Read `TZ` through this module at call time rather than importing the name, so
the tests can pin the whole service to one zone by patching it here.
"""
import datetime
import zoneinfo

TZ = zoneinfo.ZoneInfo("Europe/Kyiv")
DAY_S = 86400.0


def midnight(now, tz=None):
    """The unix instant of the local midnight that starts `now`'s day, in
    `tz` or the city's zone."""
    local = datetime.datetime.fromtimestamp(now, tz or TZ)
    return local.replace(hour=0, minute=0, second=0, microsecond=0).timestamp()
