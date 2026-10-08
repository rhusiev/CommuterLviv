"""The web app in a real browser against the real service: an account created
through the sign-in screen, a stop found by name, the bus on its board, and a
journey planned from on board it and followed.

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
    page.goto("/")
    page.get_by_role("button", name="Create an account").click()
    page.get_by_label("Username").fill(service.username(name))
    page.get_by_label("Password").fill(service.PASSWORD)
    page.get_by_role("button", name="Create the account").click()


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


def test_picking_the_route_puts_its_bus_on_the_map(page):
    _register(page, "watcher")
    expect = playwright.expect
    expect(page.get_by_text("0 vehicles")).to_be_visible()

    page.get_by_role("button", name="Routes").click()
    page.get_by_role("button", name="1", exact=True).click()

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
    page.get_by_role("button", name="Routes").click()
    page.get_by_role("button", name="1", exact=True).click()
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
