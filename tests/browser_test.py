"""The web app in a real browser against the real service: an account created
through the sign-in screen, a stop found by name, the bus on its board, and a
journey planned from on board it and followed, a place found by name planned
to and a name that matches nothing, one followed on foot that misses its bus searched again, a refused
location, a changed password and a cancelled one, one that cannot be cancelled
while under way, none offered where the service turns it off, and a shared link
that opens its stop or route.

Needs the built web app (`npm run build` in `web/`), Playwright for Python and a
Chromium. Skipped when any of them is missing."""
import contextlib
import json
import math
import os
import re
import shutil
import socket
import subprocess
import threading
import time
import urllib.request
from pathlib import Path

import pytest
import uvicorn

from commuterlviv.live import app, journeys

from . import city, service, streets

playwright = pytest.importorskip("playwright.sync_api")

WEB = Path(__file__).resolve().parent.parent / "web"
HOST = "127.0.0.1"
CHROMIUM = ("chromium-browser", "chromium", "google-chrome")
START_S = 30.0
SEE_MS = 20_000          # the bus reaches the page a few feed polls after it set off
VIEWPORT = {"width": 1280, "height": 720}
# The whole line fits across the middle of the page, at about 6 m a pixel
ZOOM = 13.0
TILE_PX = 512            # maplibre's world is this many pixels across at zoom 0
# Clicks along the line from its start, this far apart - closer than the
# vehicle badge is wide - and no further than the bus gets in a minute
STEP_PX = 8
SCAN_PX = 120
CENTRE = city._point(city.LENGTH / 2)
# Slow enough that riding beats walking the whole line: the side street takes
# 360 s, in time for the bus's next lap, which the plan rides. Chosen
WALK_KMH = 3
END = city._point(city.LENGTH)
MISSED_S = 60            # the bus left this long before the page loaded
# Most starts, the service plans the door to the end on foot alone from about 2
# to 28 s in, so a ride is asked for until this long. 60 s is chosen
RIDE_S = 60.0
ASK_EVERY_MS = 1000


def _chromium():
    """A Chromium to drive: the one named in the environment, or the system's."""
    path = os.environ.get("COMMUTERLVIV_TEST_CHROMIUM")
    return path or next(filter(None, map(shutil.which, CHROMIUM)), None)


def _bound():
    """A listening socket on a port the system picked."""
    sock = socket.socket()
    sock.bind((HOST, 0))
    return sock


def _free_port():
    with _bound() as sock:
        return sock.getsockname()[1]


def _wait_for(url):
    deadline = time.monotonic() + START_S
    while True:
        try:
            urllib.request.urlopen(url, timeout=1.0)
            return
        except OSError:
            if time.monotonic() > deadline:
                raise
            time.sleep(0.2)


@contextlib.contextmanager
def _api(application):
    """The service in a thread of this process, so it sees the monkeypatched
    feed; its port."""
    sock = _bound()
    port = sock.getsockname()[1]
    server = uvicorn.Server(uvicorn.Config(application, log_level="warning"))
    thread = threading.Thread(target=server.run, kwargs={"sockets": [sock]},
                              daemon=True)
    thread.start()
    try:
        _wait_for(f"http://{HOST}:{port}/api/health")
        yield port
    finally:
        server.should_exit = True
        thread.join(START_S)
        sock.close()


@contextlib.contextmanager
def _preview(api_port, port):
    """The built web app served by `vite preview`, proxying to the service.
    Vite binds the port itself, so another process could take it first; then
    `--strictPort` fails the test rather than serving somewhere else."""
    env = dict(os.environ, COMMUTERLVIV_API=f"http://{HOST}:{api_port}")
    proc = subprocess.Popen(
        ["npx", "vite", "preview", "--host", HOST, "--port", str(port), "--strictPort"],
        cwd=WEB, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        _wait_for(f"http://{HOST}:{port}/")
        yield
    finally:
        proc.terminate()
        proc.wait(START_S)


@pytest.fixture
def site(monkeypatch, tmp_path, net, database):
    if not (WEB / "dist" / "index.html").exists():
        pytest.skip("the web app is not built - npm run build in web/")
    if shutil.which("npx") is None:
        pytest.skip("npx is not installed")
    web_port = _free_port()
    origin = f"http://{HOST}:{web_port}"
    service.isolate(monkeypatch, tmp_path)
    found = streets.load(net, tmp_path)
    monkeypatch.setattr(journeys.Planner, "maybe",
                        classmethod(lambda cls, net, cat, log: cls(*found, cat)))
    application = app.build(service.settings_for(database, origin), net)
    with _api(application) as api_port, _preview(api_port, web_port):
        yield origin


@pytest.fixture
def page(site):
    chromium = _chromium()
    if chromium is None:
        pytest.skip("no Chromium found - set COMMUTERLVIV_TEST_CHROMIUM")
    with playwright.sync_playwright() as p:
        browser = p.chromium.launch(executable_path=chromium)
        context = browser.new_context(
            locale="en-US", base_url=site, viewport=VIEWPORT,
            permissions=["geolocation"],
            geolocation={"latitude": city.LAT, "longitude": city.LON})
        view = {"lat": CENTRE[0], "lon": CENTRE[1], "zoom": ZOOM}
        context.add_init_script(
            f"localStorage.setItem('commuterlviv.view', {json.dumps(json.dumps(view))})")
        # map tiles and fonts are someone else's servers; the test needs none
        context.route("**/*", lambda route: route.continue_()
                      if route.request.url.startswith(site) else route.abort())
        yield context.new_page()
        browser.close()


def _register(page, name):
    """Creates an account named after `name`; the username it took."""
    username = service.username(name)
    page.goto("/")
    page.get_by_role("button", name="Create an account").click()
    page.get_by_label("Username").fill(username)
    page.get_by_label("Password").fill(service.PASSWORD)
    page.get_by_role("button", name="Create the account").click()
    return username


def test_a_new_user_finds_a_stop_and_sees_the_bus_coming(page):
    _register(page, "rider")

    page.get_by_placeholder("Find a stop or a place").fill("Stop 4")
    page.get_by_role("button", name="Stop 4").first.click()

    expect = playwright.expect
    expect(page.get_by_role("heading", name="Stop 4")).to_be_visible()
    # a row per route: its badge, which shows the number without the bus's
    # letter, and a countdown
    expect(page.get_by_role("button", name=re.compile(r"^1 \d+ min$"))).to_be_visible(
        timeout=SEE_MS)


def test_a_saved_place_is_offered_above_the_stops_it_matches(page):
    _register(page, "saver")
    search = page.get_by_placeholder("Find a stop or a place")
    search.fill("Stop 4")
    page.get_by_title("Save this place").first.click()

    search.fill("stop 4")
    rows = page.locator("ul li")
    expect = playwright.expect
    expect(rows.first).to_contain_text("Saved places")
    expect(rows.first).to_contain_text("Stop 4")
    expect(rows.first.get_by_title("Save this place")).to_have_count(0)
    expect(rows.nth(1)).to_contain_text("Stops")


def test_a_name_nothing_matches_is_said_to_match_nothing(page):
    _register(page, "seeker")
    page.route("**/api/search?**", lambda route: route.fulfill(json={"places": []}))
    page.get_by_placeholder("Find a stop or a place").fill("Nowhere at all")

    playwright.expect(page.get_by_text("No stop or place by that name")).to_be_visible()


def test_a_place_found_by_name_is_shown_and_the_way_there_planned(page):
    _register(page, "visitor")
    found = {"name": "Town hall", "where": "Market square",
             "lat": END[0], "lon": END[1], "kind": None}
    # the geocoder is OpenStreetMap's, which the test does not reach
    page.route("**/api/search?**", lambda route: route.fulfill(json={"places": [found]}))
    page.get_by_placeholder("Find a stop or a place").fill("Town hall")
    page.get_by_role("button", name=re.compile(r"^Town hall")).click()

    expect = playwright.expect
    expect(page.get_by_role("heading", name="Town hall")).to_be_visible()
    expect(page.get_by_text("Market square")).to_be_visible()
    with page.expect_request(lambda r: "/api/plan?from=" in r.url) as asked:
        page.get_by_role("button", name="Get here").click()

    ends = dict(part.split("=") for part in asked.value.url.split("?")[1].split("&"))
    assert tuple(map(float, ends["from"].split(","))) == pytest.approx((city.LAT, city.LON))
    assert tuple(map(float, ends["to"].split(","))) == pytest.approx(END)
    expect(page.get_by_text("Town hall", exact=True)).to_be_visible()


def _pick_route(page):
    """Picks the city's one route from the routes tab."""
    page.get_by_role("button", name="Routes").click()
    page.get_by_role("button", name="1", exact=True).click()


def test_picking_the_route_puts_its_bus_on_the_map(page):
    _register(page, "watcher")
    expect = playwright.expect
    expect(page.get_by_text("0 vehicles")).to_be_visible()

    _pick_route(page)

    expect(page.get_by_text("1 on")).to_be_visible()
    expect(page.get_by_text("1 vehicles")).to_be_visible(timeout=SEE_MS)


def _on_page(lat, lon):
    """Where on the page the map draws `lat`, `lon`: web Mercator about the
    view the page starts at, which is centred."""
    world = TILE_PX * 2 ** ZOOM

    def x(lo):
        return lo / 360 * world

    def y(la):
        return -math.log(math.tan(math.pi / 4 + math.radians(la) / 2)) / (2 * math.pi) * world

    return (VIEWPORT["width"] / 2 + x(lon) - x(CENTRE[1]),
            VIEWPORT["height"] / 2 + y(lat) - y(CENTRE[0]))


def _board_the_bus(page):
    """Clicks along the line from its start until the bus's card opens."""
    expect = playwright.expect
    x0, y0 = _on_page(city.LAT, city.LON)
    card = page.get_by_role("heading", name="Stops ahead")
    for dx in range(0, SCAN_PX, STEP_PX):
        page.mouse.click(x0 + dx, y0)
        if card.is_visible():
            break
    expect(card).to_be_visible()
    page.get_by_role("button", name="I'm on it").click()


def test_a_journey_planned_on_board_is_followed_from_the_ride(page):
    _register(page, "aboard")
    expect = playwright.expect
    _pick_route(page)
    expect(page.get_by_text("1 vehicles")).to_be_visible(timeout=SEE_MS)
    page.get_by_role("button", name="Map", exact=True).click()

    _board_the_bus(page)
    panel = page.locator("aside")
    expect(panel.get_by_role("button", name=re.compile("On board"))).to_be_visible()
    panel.get_by_role("button", name="Find a stop or a place").click()
    panel.get_by_role("button", name="Choose on the map").click()
    page.mouse.click(*_on_page(*streets.DOOR))
    panel.get_by_role("button", name="Find a way").click()
    panel.get_by_text(re.compile(r"^\d+ min$")).first.click()
    panel.get_by_role("button", name="Follow it").click()
    page.get_by_title("Show every step of the journey").click()

    steps = page.locator("ol li")
    expect(steps.first).to_contain_text(re.compile(r"\d\d:\d\d - \d\d:\d\d.*Stop \d → Stop 2"))
    expect(steps.last).to_contain_text("Walk to the door")
    expect(page.locator("li[aria-current=step]")).to_contain_text("→")


def _a_ride_from_the_door(page):
    """A journey planned from the door to the end of the line that rides the
    bus, as the service plans it, with the catalog it belongs to."""
    tag = page.evaluate("fetch('/api/catalog').then(r => r.headers.get('ETag'))")
    lat, lon = streets.DOOR
    deadline = time.monotonic() + RIDE_S
    while True:
        plan = page.evaluate(
            f"fetch('/api/plan?from={lat},{lon}&to={END[0]},{END[1]}"
            f"&speed={WALK_KMH}').then(r => r.json())")
        journey = next((o for o in plan["options"]
                        if any(leg["kind"] == "ride" for leg in o["legs"])), None)
        if journey is not None or time.monotonic() > deadline:
            break
        page.wait_for_timeout(ASK_EVERY_MS)
    assert journey is not None, plan
    return journey, tag


def test_a_missed_bus_is_searched_again_from_the_last_fix(page):
    _register(page, "late")
    expect = playwright.expect
    _pick_route(page)
    expect(page.get_by_text("1 vehicles")).to_be_visible(timeout=SEE_MS)
    journey, tag = _a_ride_from_the_door(page)
    ride = next(leg for leg in journey["legs"] if leg["kind"] == "ride")
    ride["dep"] = time.time() - MISSED_S
    ride.pop("veh", None)
    held = {"journey": journey, "to": {"lat": END[0], "lon": END[1]}, "tag": tag}
    page.evaluate("v => localStorage.setItem('commuterlviv.following', v)",
                  json.dumps(held))
    page.context.set_geolocation(
        {"latitude": streets.DOOR[0], "longitude": streets.DOOR[1]})
    page.reload()

    again = page.get_by_role("button", name="Search again")
    expect(again).to_be_visible(timeout=SEE_MS)
    # The map and the follower watch the position already; asked again, the
    # browser would not answer until it moved
    with page.expect_request(lambda r: "/api/plan?from=" in r.url) as asked:
        again.click()
    lat, lon = asked.value.url.split("from=")[1].split("&")[0].split(",")
    assert (float(lat), float(lon)) == pytest.approx(streets.DOOR)


def test_a_refused_location_says_how_to_allow_it(page):
    _register(page, "hidden")
    page.context.clear_permissions()

    page.get_by_role("button", name="Stops near me").click()

    playwright.expect(page.get_by_text(
        "Location is blocked for this page")).to_be_visible(timeout=SEE_MS)


def test_a_changed_password_is_the_one_that_signs_in(page):
    username = _register(page, "changer")
    renewed = service.PASSWORD + "-renewed"

    page.get_by_role("button", name="Account", exact=True).click()
    page.get_by_role("button", name="Change password").click()
    page.get_by_label("Current password").fill(service.PASSWORD)
    page.get_by_label("New password").fill(renewed)
    page.get_by_role("button", name="Change password").click()
    playwright.expect(page.get_by_text("Password changed")).to_be_visible(timeout=SEE_MS)
    page.get_by_role("button", name="Sign out").click()
    page.get_by_label("Username").fill(username)
    page.get_by_label("Password").fill(renewed)
    page.get_by_role("button", name="Sign in").click()

    playwright.expect(page.get_by_placeholder("Find a stop or a place")).to_be_visible(
        timeout=SEE_MS)


def test_a_cancelled_password_change_forgets_what_was_typed(page):
    _register(page, "canceller")
    page.get_by_role("button", name="Account", exact=True).click()
    page.get_by_role("button", name="Change password").click()
    page.get_by_label("Current password").fill(service.PASSWORD)
    page.get_by_label("New password").fill(service.PASSWORD + "-unsent")
    page.get_by_role("button", name="Cancel").click()

    page.get_by_role("button", name="Change password").click()

    playwright.expect(page.get_by_label("Current password")).to_have_value("")
    playwright.expect(page.get_by_label("New password")).to_have_value("")


def test_a_password_change_under_way_cannot_be_cancelled(page):
    _register(page, "patient")
    held = []
    page.route("**/api/password", lambda route: held.append(route))
    page.get_by_role("button", name="Account", exact=True).click()
    page.get_by_role("button", name="Change password").click()
    page.get_by_label("Current password").fill(service.PASSWORD)
    page.get_by_label("New password").fill(service.PASSWORD + "-renewed")
    page.get_by_role("button", name="Change password").click()

    playwright.expect(page.get_by_role("button", name="Cancel")).to_be_disabled()
    held[0].continue_()
    playwright.expect(page.get_by_text("Password changed")).to_be_visible(timeout=SEE_MS)


def test_changing_the_password_is_not_offered_where_the_service_turns_it_off(page):
    def turned_off(route):
        got = route.fetch()
        route.fulfill(response=got, json={**got.json(), "password_change": False})

    page.route("**/api/me", turned_off)
    _register(page, "unoffered")
    page.get_by_role("button", name="Account", exact=True).click()

    expect = playwright.expect
    expect(page.get_by_role("button", name="Sign out")).to_be_visible()
    expect(page.get_by_role("button", name="Change password")).to_have_count(0)

def test_a_shared_link_opens_its_stop_or_route(page):
    _register(page, "linked")
    expect = playwright.expect
    # signed in once the map is up
    expect(page.get_by_text("0 vehicles")).to_be_visible()

    page.goto("/?stop=s4")
    expect(page.get_by_role("heading", name="Stop 4")).to_be_visible()

    page.goto(f"/?route={city.ROUTE}&tab=route")
    expect(page.get_by_text("Stop 0 - Stop 4")).to_be_visible()
