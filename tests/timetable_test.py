"""The timetable the planner searches, built for the network it is given."""
import io
import os
import time
import zipfile

from commuterlviv import gtfs, localtime, plan

from . import city


def _idle_feed():
    """The city's feed with a calendar that runs none of its services."""
    out = io.BytesIO()
    with zipfile.ZipFile(io.BytesIO(city.feed())) as src, \
            zipfile.ZipFile(out, "w") as dst:
        for name in src.namelist():
            body = src.read(name).decode()
            if name == "calendar.txt":
                head, *rows = body.splitlines()
                body = "\n".join([head] + [
                    ",".join("0" if v == "1" else v for v in row.split(","))
                    for row in rows]) + "\n"
            dst.writestr(name, body)
    return out.getvalue()


class _Served:
    """What `requests.get` answers for the feed."""

    def __init__(self, content):
        self.content = content

    def raise_for_status(self):
        pass


def test_the_timetable_runs_the_feed_its_network_was_built_from(net, monkeypatch):
    stale = time.time() - 2 * gtfs.MAX_AGE
    os.utime(gtfs.ZIP, (stale, stale))
    monkeypatch.setattr(gtfs, "PREV", gtfs.ZIP.with_name("static.prev.zip"))
    monkeypatch.setattr(gtfs.requests, "get", lambda *a, **kw: _Served(_idle_feed()))

    day = plan.Timetable(net).on(localtime.midnight(city.at(city.SEARCH_AT)))

    started = sum(int((p.times[:, 0] < localtime.DAY_S).sum()) for p in day.patterns)
    assert started == len(net.trip_stops)
