"""Which services run on a day: the weekday, then the calendar's date window.

Nothing else in the suite reads this window, which is how the test city came to
hold one that expired at the end of 2026: the whole suite would have stopped
planning trips on 2027-01-01, and no assertion would have said why.
"""
import csv
import datetime
import io
import zipfile

from commuterlviv import gtfs

from . import city

MONDAY = datetime.date(2026, 10, 5)


def _weekly(first: str, last: str, days=("monday",)) -> dict:
    row = {"service_id": "all", "start_date": first, "end_date": last}
    row.update({day: "1" if day in days else "0" for day in gtfs.Calendar.DAYS})
    return row


def test_a_service_runs_on_its_weekday_inside_its_window() -> None:
    calendar = gtfs.Calendar(weekly=[_weekly("20260101", "20261231")])

    assert calendar.runs("all", MONDAY)
    assert not calendar.runs("all", MONDAY + datetime.timedelta(days=1))


def test_a_day_after_the_window_ends_runs_nothing() -> None:
    calendar = gtfs.Calendar(weekly=[_weekly("20260101", "20260930")])

    assert not calendar.runs("all", MONDAY)


def test_a_day_before_the_window_starts_runs_nothing() -> None:
    calendar = gtfs.Calendar(weekly=[_weekly("20261006", "20261231")])

    assert not calendar.runs("all", MONDAY)


def test_the_test_city_feed_keeps_running_past_2026() -> None:
    """The bug this guards: the feed's calendar ended at 20261231, so every
    service stopped running and the suite would have failed from 2027-01-01
    with nothing to say why."""
    with zipfile.ZipFile(io.BytesIO(city.feed())) as archive:
        with archive.open("calendar.txt") as raw:
            rows = list(csv.DictReader(io.TextIOWrapper(raw, "utf-8")))
    calendar = gtfs.Calendar(weekly=rows)

    assert calendar.runs("all", datetime.date(2027, 1, 1))
    assert calendar.runs("all", datetime.date(2099, 12, 31))
