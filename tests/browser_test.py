"""The web app in a real browser against the real service: an account created
through the sign-in screen, a stop found by name, the bus on its board, a
pinned stop listed once in the Mine tab and an old Times link opening it, a route
watched from the stop's card and from what is due there, a line's stops each way
with its bus coming, an old line link opening the Lines tab, a journey planned
from on board the bus and followed, a place found by name planned to and a name
that matches nothing, what opens on an option only once it is picked, one
followed on foot that misses its bus searched again, a refused location, a
changed password and a cancelled one, one that cannot be cancelled while under
way, none offered where the service turns it off, and a shared link that opens
its stop or route.

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
PHONE = {"width": 393, "height": 852}
TAP_PX = 44              # the smallest target WCAG 2.5.5 allows, in CSS pixels
DARK = 128               # a colour channel below this reads as dark on the map
# The whole line fits across the middle of the page, at about 6 m a pixel
ZOOM = 13.0
ALL_STOPS_ZOOM = 16      # the web's own: every stop is drawn and clicked from here
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
    expect = playwright.expect
    # the row names its routes by their badges, not by the feed's "А1"
    row = page.get_by_role("button", name="Stop 4 1", exact=True)
    expect(row).to_be_visible()
    expect(row).not_to_contain_text("А1")
    row.click()

    expect(page.get_by_role("heading", name="Stop 4")).to_be_visible()
    # its code as a name carries one, not as the feed's bare field
    expect(page.get_by_text("(104)", exact=True)).to_be_visible()
    # a row per route: its badge, which shows the number without the bus's
    # letter, and a countdown
    expect(page.get_by_role("button", name=re.compile(r"^1 \d+ min$"))).to_be_visible(
        timeout=SEE_MS)


def test_a_pinned_stop_is_listed_once_in_the_mine_tab(page):
    _register(page, "pinner")
    page.get_by_placeholder("Find a stop or a place").fill("Stop 4")
    page.get_by_role("button", name="Stop 4").first.click()
    page.get_by_role("button", name="Pin", exact=True).click()

    page.get_by_role("button", name="Mine", exact=True).click()

    expect = playwright.expect
    expect(page.get_by_role("heading", name="Pinned stops")).to_be_visible()
    expect(page.get_by_role("button", name="Stop 4", exact=True)).to_have_count(1)
    expect(page.get_by_role("button", name="Account", exact=True)).to_have_count(0)


def test_an_old_times_link_opens_the_mine_tab(page):
    _register(page, "linker")
    playwright.expect(page.get_by_text("0 vehicles")).to_be_visible()

    page.goto("/?tab=times")

    playwright.expect(page.get_by_role("heading", name="Pinned stops")).to_be_visible(
        timeout=SEE_MS)


def test_a_route_that_calls_at_a_stop_is_watched_from_its_card(page):
    _register(page, "caller")
    expect = playwright.expect
    expect(page.get_by_text("0 vehicles")).to_be_visible()
    page.get_by_placeholder("Find a stop or a place").fill("Stop 4")
    page.get_by_role("button", name="Stop 4").first.click()
    expect(page.get_by_text("Calls here")).to_be_visible()
    chip = page.get_by_role("button", name="1", exact=True)

    chip.click()
    expect(page.get_by_text("1 vehicles")).to_be_visible(timeout=SEE_MS)
    chip.click()
    expect(page.get_by_text("0 vehicles")).to_be_visible()

    # a right click is no longer a way to the line: the chip's `›` is
    chip.click(button="right")
    expect(page.get_by_text("Stop 0 - Stop 4")).not_to_be_visible()
    page.get_by_role("button", name="Line А1").last.click()
    expect(page.get_by_text("Stop 0 - Stop 4")).to_be_visible()
    page.get_by_role("button", name="Back").click()
    expect(page.get_by_text("0 on")).to_be_visible()


def test_a_route_due_at_a_stop_is_watched_from_its_countdown(page):
    _register(page, "due")
    expect = playwright.expect
    expect(page.get_by_text("0 vehicles")).to_be_visible()
    page.get_by_placeholder("Find a stop or a place").fill("Stop 4")
    page.get_by_role("button", name="Stop 4").first.click()
    due = page.get_by_role("button", name=re.compile(r"^1 \d+ min$"))

    due.click(timeout=SEE_MS)
    expect(page.get_by_text("1 vehicles")).to_be_visible(timeout=SEE_MS)
    expect(due).to_have_attribute("aria-pressed", "true")


def _zoom_to(page, zoom):
    """Zooms in from the keyboard, a step at a time, about the centre."""
    page.locator(".maplibregl-canvas").focus()
    for z in range(int(ZOOM) + 1, zoom + 1):
        page.keyboard.press("Equal")
        page.wait_for_function(
            f"JSON.parse(localStorage.getItem('commuterlviv.view')).zoom > {z} - 0.01")


def test_a_stop_no_watched_route_calls_at_opens_from_close_in(page):
    _register(page, "stroller")
    expect = playwright.expect
    expect(page.get_by_text("0 vehicles")).to_be_visible()
    card = page.get_by_role("heading", name="Stop 2")
    at = (VIEWPORT["width"] / 2, VIEWPORT["height"] / 2)

    page.mouse.click(*at)
    expect(card).not_to_be_visible()

    _zoom_to(page, ALL_STOPS_ZOOM)
    page.mouse.click(*at)
    expect(card).to_be_visible()


def test_a_line_lists_its_stops_each_way_with_the_bus_coming(page):
    _register(page, "rider")
    expect = playwright.expect
    page.get_by_role("button", name="Lines", exact=True).click()
    page.get_by_role("button", name="Line А1").click()
    way = page.get_by_title("The other way")
    stops = page.get_by_role("listitem").filter(has_text=re.compile(r"^Stop \d"))

    expect(way).to_have_text(f"→ Stop {city.STOPS - 1}")
    expect(stops.first).to_contain_text("Stop 0")
    expect(stops).to_have_count(city.STOPS)
    expect(page.get_by_label("A vehicle heading here")).to_have_count(1, timeout=SEE_MS)
    expect(page.get_by_role("list").get_by_text(re.compile(r"^(Now|\d+ min)$")).first).to_be_visible()

    way.click()

    expect(way).to_have_text("→ Stop 0")
    expect(stops.first).to_contain_text(f"Stop {city.STOPS - 1}")


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


def _hold(page, x=VIEWPORT["width"] / 2, y=VIEWPORT["height"] / 2):
    """Right-clicks the map at `x`, `y` - by default its middle, CENTRE - once
    it is up; the menu it opens."""
    page.locator(".maplibregl-canvas").wait_for()
    page.mouse.click(x, y, button="right")
    menu = page.get_by_role("dialog", name="This place")
    playwright.expect(menu).to_be_visible()
    return menu


def test_a_place_held_on_the_map_is_named_in_its_menu(page):
    _register(page, "namer")
    page.on("dialog", lambda dialog: pytest.fail(f"asked in a {dialog.type}"))
    menu = _hold(page)
    menu.get_by_role("button", name="Save this place...").click()
    menu.get_by_label("Name this place").fill("Corner")
    menu.get_by_role("button", name="Save").click()

    expect = playwright.expect
    expect(menu).not_to_be_visible()
    page.get_by_placeholder("Find a stop or a place").fill("Corner")
    # starred: a saved place, not a stop or a found one
    expect(page.locator("ul li").first).to_have_text("Corner★")


def test_the_way_to_a_place_held_on_the_map_is_planned_from_its_menu(page):
    _register(page, "wayfarer")
    with page.expect_request(lambda r: "/api/plan?from=" in r.url) as asked:
        _hold(page).get_by_role("button", name="Directions to here").click()

    ends = dict(part.split("=") for part in asked.value.url.split("?")[1].split("&"))
    assert tuple(map(float, ends["to"].split(","))) == pytest.approx(CENTRE, abs=1e-3)


def test_the_stops_near_a_place_held_on_the_map_are_listed_from_its_menu(page):
    _register(page, "browser")
    _hold(page).get_by_role("button", name="Stops near here").click()

    first = page.locator("ul li").first
    playwright.expect(first).to_contain_text("Stop 2")
    playwright.expect(first).to_contain_text(re.compile(r"\d+ m"))


def test_a_place_held_far_from_every_stop_is_said_to_have_none_near(page):
    _register(page, "wanderer")
    # a corner of the map is some 12 km out at ZOOM; the city is 2 km long
    _hold(page, 10, VIEWPORT["height"] - 100).get_by_role(
        "button", name="Stops near here").click()

    playwright.expect(page.get_by_text("No stop within 2 km of this place")).to_be_visible()


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


def _plan_to_town_hall(page):
    """Opens the planner from the place card of a place found by name at END,
    from where the browser is"""
    found = {"name": "Town hall", "where": "", "lat": END[0], "lon": END[1], "kind": None}
    page.route("**/api/search?**", lambda route: route.fulfill(json={"places": [found]}))
    page.get_by_placeholder("Find a stop or a place").fill("Town hall")
    page.get_by_role("button", name=re.compile(r"^Town hall")).click()
    page.get_by_role("button", name="Get here").click()


def test_a_start_where_i_am_says_so_rather_than_its_coordinates(page):
    _register(page, "here")
    _plan_to_town_hall(page)

    panel = page.locator("aside")
    expect = playwright.expect
    expect(panel.get_by_text("Where I am", exact=True)).to_be_visible()
    expect(panel.get_by_text(re.compile(r"^[\d.]+, [\d.]+$"))).to_have_count(0)


def test_the_ends_are_the_same_shape_as_the_time_to_leave(page):
    _register(page, "shaper")
    _plan_to_town_hall(page)

    panel = page.locator("aside")
    end = panel.get_by_role("button", name="Town hall")
    leave = panel.locator("input[type=datetime-local]")
    playwright.expect(end).to_be_visible()
    radius = "e => getComputedStyle(e).borderRadius"
    assert end.evaluate(radius) == leave.evaluate(radius)


def _plan_a_ride(page, confidence, hurry=False, backup=0):
    """Plans the way to END, answered with one option that rides the city's
    route on what `confidence` names, caught only by hurrying if `hurry` says
    so, with `backup` backups, and leaves that option unpicked. Its card, and
    the length on it, which picks and folds it."""
    now = int(time.time())
    ride = {"kind": "ride", "dep": now + 60, "arr": now + 600, "a": 0, "b": city.STOPS - 1,
            "route": 0, "live": False, "confidence": confidence, "backups": []}
    walk = {"kind": "walk", "dep": now, "arr": now + 60, "a": -1, "b": 0, "pts": []}
    home = {"kind": "walk", "dep": now + 600, "arr": now + 660, "a": city.STOPS - 1,
            "b": -1, "pts": []}
    option = {"dep": now, "arr": now + 660, "rides": 1, "live": False, "hurry": hurry,
              "confidence": confidence, "backup": backup, "legs": [walk, ride, home]}
    page.route("**/api/plan?**", lambda route: route.fulfill(
        json={"t": now, "report": "r1", "options": [option]}))
    _plan_to_town_hall(page)
    minutes = re.compile(r"^\d+ min$")
    card = page.locator("aside .inset-panel").filter(has=page.get_by_text(minutes))
    # the first of them; the walks say theirs too, once it is picked
    length = card.get_by_text(minutes).first
    playwright.expect(length).to_be_visible()
    return card, length


@pytest.mark.parametrize("word", ["Line unseen", "Hurry", "1 backup"])
def test_everything_on_an_unpicked_option_picks_it(page, word):
    _register(page, "picker")
    card, _ = _plan_a_ride(page, "quiet", hurry=True, backup=1)
    expect = playwright.expect
    expect(card.get_by_role("button")).to_have_count(1)

    card.get_by_text(re.compile(f"^{word}")).click()

    expect(card.get_by_role("button", expanded=True)).to_be_visible()


def test_a_picked_option_folds_again_from_its_summary(page):
    _register(page, "folder")
    card, length = _plan_a_ride(page, "live")
    expect = playwright.expect
    stop = card.get_by_role("button", name=f"Stop {city.STOPS - 1}")
    length.click()
    expect(stop).to_be_visible()

    length.click()

    expect(card.get_by_role("button", expanded=False)).to_be_visible()
    expect(stop).to_have_count(0)


def test_a_picked_option_says_its_notes_and_hurry_in_place(page):
    _register(page, "curious")
    card, length = _plan_a_ride(page, "terminus", hurry=True)
    expect = playwright.expect
    why = card.get_by_text("The vehicle has not set off")
    hint = card.get_by_text("Only hurrying to the first stop catches this bus")
    expect(why).to_have_count(0)
    expect(hint).to_have_count(0)

    length.click()

    expect(why).to_be_visible()
    expect(hint).to_be_visible()
    expect(card.get_by_role("button", name=re.compile("^(Next trip|Hurry)"))).to_have_count(0)


def test_every_target_on_a_picked_option_is_big_enough_to_tap(page):
    _register(page, "tapper")
    card, length = _plan_a_ride(page, "terminus", hurry=True, backup=1)
    length.click()
    targets = card.get_by_role("button")
    # the summary, the two stops, the line and the backups; with no footpaths
    # to follow it by, the option offers no following
    playwright.expect(targets.nth(4)).to_be_visible()

    small = [(targets.nth(i).inner_text(), box) for i in range(targets.count())
             if min((box := targets.nth(i).bounding_box())["width"], box["height"]) < TAP_PX]

    assert small == []
    assert targets.count() == 5


def test_a_line_opens_from_its_badge_marked_with_a_map(page):
    _register(page, "liner")
    card, length = _plan_a_ride(page, "live")
    expect = playwright.expect
    line = page.get_by_text("Stop 0 - Stop 4")
    badge = card.get_by_title("Show this line")
    length.click()
    # its vehicle's, and the map
    expect(badge.locator("svg")).to_have_count(2)
    expect(line).to_have_count(0)

    badge.click()

    expect(line).to_be_visible()


def test_a_stop_opens_from_its_row_marked_with_a_chevron(page):
    _register(page, "stopper")
    card, length = _plan_a_ride(page, "live")
    expect = playwright.expect
    heading = page.get_by_role("heading", name=f"Stop {city.STOPS - 1}")
    row = card.get_by_role("button", name=f"Stop {city.STOPS - 1}")
    length.click()
    # its icon, and the chevron
    expect(row.locator("svg")).to_have_count(2)
    expect(heading).to_have_count(0)

    row.click()

    expect(heading).to_be_visible()


def test_an_option_says_its_length_on_one_line_on_a_phone(page):
    _register(page, "narrow")
    page.set_viewport_size(PHONE)
    _, length = _plan_a_ride(page, "quiet", hurry=True, backup=1)

    tops = length.evaluate(
        "el => { const r = document.createRange(); r.selectNodeContents(el);"
        " return new Set([...r.getClientRects()].map((c) => Math.round(c.top))).size }")

    assert tops == 1


def _pick_route(page):
    """Picks the city's one route from the Lines tab."""
    page.get_by_role("button", name="Lines", exact=True).click()
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
    page.get_by_role("button", name="Map", exact=True).click()
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
    # keeping the screen on is a setting, offered as a switch
    awake = page.get_by_role("switch", name="Keep screen on")
    expect(awake).to_have_attribute("aria-checked", "false")
    awake.click()
    expect(awake).to_have_attribute("aria-checked", "true")
    # The map and the follower watch the position already; asked again, the
    # browser would not answer until it moved
    with page.expect_request(lambda r: "/api/plan?from=" in r.url) as asked:
        again.click()
    lat, lon = asked.value.url.split("from=")[1].split("&")[0].split(",")
    assert (float(lat), float(lon)) == pytest.approx(streets.DOOR)


def test_the_step_followed_on_a_phone_is_not_cut_short_by_its_buttons(page):
    _register(page, "reader")
    expect = playwright.expect
    _pick_route(page)
    expect(page.get_by_text("1 vehicles")).to_be_visible(timeout=SEE_MS)
    page.get_by_role("button", name="Map", exact=True).click()
    journey, tag = _a_ride_from_the_door(page)
    held = {"journey": journey, "to": {"lat": END[0], "lon": END[1]}, "tag": tag}
    page.evaluate("v => localStorage.setItem('commuterlviv.following', v)",
                  json.dumps(held))
    page.evaluate("localStorage.setItem('commuterlviv.lang', 'uk')")
    page.context.set_geolocation(
        {"latitude": streets.DOOR[0], "longitude": streets.DOOR[1]})
    page.set_viewport_size(PHONE)
    page.reload()

    head = page.get_by_text(re.compile("^Ідіть до"))
    expect(head).to_be_visible(timeout=SEE_MS)
    clipped = head.evaluate("e => e.scrollWidth > e.clientWidth"
                            " || e.scrollHeight > e.clientHeight")
    assert not clipped


def test_a_refused_location_says_how_to_allow_it(page):
    _register(page, "hidden")
    page.context.clear_permissions()

    page.get_by_role("button", name="Stops near me").click()

    playwright.expect(page.get_by_text(
        "Location is blocked for this page")).to_be_visible(timeout=SEE_MS)


def _open_account(page, tab="Mine", row="Account"):
    """The account is the last row of the Mine tab, named with the username"""
    page.get_by_role("button", name=tab, exact=True).click()
    page.get_by_role("button", name=re.compile(f"^{row}")).click()


def test_a_changed_password_is_the_one_that_signs_in(page):
    username = _register(page, "changer")
    renewed = service.PASSWORD + "-renewed"

    _open_account(page)
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
    _open_account(page)
    page.get_by_role("button", name="Change password").click()
    page.get_by_label("Current password").fill(service.PASSWORD)
    page.get_by_label("New password").fill(service.PASSWORD + "-unsent")
    page.get_by_role("button", name="Cancel", exact=True).click()

    page.get_by_role("button", name="Change password").click()

    playwright.expect(page.get_by_label("Current password")).to_have_value("")
    playwright.expect(page.get_by_label("New password")).to_have_value("")


def test_a_password_change_under_way_cannot_be_cancelled(page):
    _register(page, "patient")
    held = []
    page.route("**/api/password", lambda route: held.append(route))
    _open_account(page)
    page.get_by_role("button", name="Change password").click()
    page.get_by_label("Current password").fill(service.PASSWORD)
    page.get_by_label("New password").fill(service.PASSWORD + "-renewed")
    page.get_by_role("button", name="Change password").click()

    playwright.expect(page.get_by_role("button", name="Cancel", exact=True)).to_be_disabled()
    held[0].continue_()
    playwright.expect(page.get_by_text("Password changed")).to_be_visible(timeout=SEE_MS)


def test_changing_the_password_is_not_offered_where_the_service_turns_it_off(page):
    def turned_off(route):
        got = route.fetch()
        route.fulfill(response=got, json={**got.json(), "password_change": False})

    page.route("**/api/me", turned_off)
    _register(page, "unoffered")
    _open_account(page)

    expect = playwright.expect
    expect(page.get_by_role("button", name="Sign out")).to_be_visible()
    expect(page.get_by_role("button", name="Change password")).to_have_count(0)

def test_the_walking_speed_reads_on_one_line_in_ukrainian(page):
    _register(page, "walker")
    # signed in once the map is up
    playwright.expect(page.get_by_text("0 vehicles")).to_be_visible()
    page.evaluate("localStorage.setItem('commuterlviv.lang', 'uk')")
    page.reload()
    _open_account(page, tab="Моє", row="Обліковий запис")

    speed = page.get_by_text("4,5 км/год", exact=True)
    playwright.expect(speed).to_be_visible()
    lines = speed.evaluate("e => { const r = document.createRange();"
                           " r.selectNodeContents(e); return r.getClientRects().length }")
    assert lines == 1


def test_the_maps_own_buttons_speak_ukrainian(page):
    _register(page, "localised")
    playwright.expect(page.get_by_text("0 vehicles")).to_be_visible()
    page.evaluate("localStorage.setItem('commuterlviv.lang', 'uk')")
    page.reload()

    expect = playwright.expect
    expect(page.get_by_role("button", name="Наблизити")).to_be_visible()
    expect(page.get_by_role("button", name="Віддалити")).to_be_visible()
    expect(page.locator(".maplibregl-ctrl-attrib-button")).to_have_attribute(
        "title", "Показати чи сховати авторство")
    expect(page.locator(".maplibregl-canvas")).to_have_attribute("aria-label", "Мапа")


def test_the_zoom_buttons_are_not_a_white_square_on_the_dark_map(page):
    _register(page, "zoomer")
    zoom = page.locator(".maplibregl-ctrl-group").filter(
        has=page.get_by_role("button", name="Zoom in"))
    playwright.expect(zoom).to_be_visible()

    assert zoom.evaluate("e => getComputedStyle(e).backgroundColor") != "rgb(255, 255, 255)"


def test_the_attribution_is_not_a_white_pill_on_the_dark_map(page):
    _register(page, "credited")
    credit = page.locator(".maplibregl-ctrl-attrib")
    # hidden here, as the test's blocked tiles credit no one
    playwright.expect(credit).to_be_attached()

    # painted over white, the worst a basemap can show through it, by a canvas
    # that reads any CSS colour, oklab included
    red, green, blue = credit.evaluate("""e => {
        const c = document.createElement("canvas").getContext("2d");
        c.fillStyle = "white";
        c.fillRect(0, 0, 1, 1);
        c.fillStyle = getComputedStyle(e).backgroundColor;
        c.fillRect(0, 0, 1, 1);
        return [...c.getImageData(0, 0, 1, 1).data.slice(0, 3)];
    }""")
    assert max(red, green, blue) < DARK


def test_the_attribution_takes_the_apps_focus_ring_not_an_inverted_one(page):
    credited = {
        "version": 8,
        "sources": {"credit": {"type": "geojson", "attribution": "© Someone",
                               "data": {"type": "FeatureCollection", "features": []}}},
        "layers": [{"id": "credit", "type": "circle", "source": "credit"}],
    }
    page.route("**/style.json", lambda route: route.fulfill(json=credited))
    _register(page, "focused")
    credit = page.locator(".maplibregl-ctrl-attrib")
    button = credit.locator(".maplibregl-ctrl-attrib-button")
    shadow = "e => getComputedStyle(e).boxShadow"

    button.click()
    # its own ring, blue in maplibre's sheet, would be drawn inverted
    assert button.evaluate(shadow) == "none"
    unfocused = credit.evaluate(shadow)
    page.keyboard.press("Shift+Tab")
    page.keyboard.press("Tab")
    playwright.expect(button).to_be_focused()
    assert credit.evaluate(shadow) != unfocused


def test_a_shared_link_opens_its_stop_or_route(page):
    _register(page, "linked")
    expect = playwright.expect
    # signed in once the map is up
    expect(page.get_by_text("0 vehicles")).to_be_visible()

    page.goto("/?stop=s4")
    expect(page.get_by_role("heading", name="Stop 4")).to_be_visible()

    page.goto(f"/?route={city.ROUTE}&tab=lines")
    expect(page.get_by_text("Stop 0 - Stop 4")).to_be_visible()


def test_an_old_line_link_opens_the_line_in_the_lines_tab(page):
    _register(page, "oldliner")
    expect = playwright.expect
    expect(page.get_by_text("0 vehicles")).to_be_visible()

    page.goto(f"/?route={city.ROUTE}&tab=route")
    expect(page.get_by_title("The other way")).to_be_visible(timeout=SEE_MS)

    page.goto("/?tab=route")
    expect(page.get_by_role("radio", name="All")).to_be_checked(timeout=SEE_MS)
