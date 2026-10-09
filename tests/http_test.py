"""The service end to end over HTTP and its websocket: a made-up feed polled
in real time, a user registered, the map and the boards read as a client would."""
import json
import time

import pytest
from starlette.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from commuterlviv import network
from commuterlviv.live import app, wire

from . import city, service

ORIGIN = "http://testserver"
WAIT_S = 15.0
ETA_TOL_S = 30.0
NEAR_DEG = 1e-3
CLIENT = ("127.0.0.1", 50000)     # the peer the app sees; it stores it as an inet


@pytest.fixture
def feed(monkeypatch, tmp_path):
    return service.isolate(monkeypatch, tmp_path)


@pytest.fixture
def client(feed, net, database):
    """The service over the city, signed in as nobody."""
    st = service.settings_for(database, ORIGIN)
    with TestClient(app.build(st, net), base_url=ORIGIN, client=CLIENT) as c:
        yield c


def _signed_in(client, name):
    r = client.post("/api/register", headers={"Origin": ORIGIN},
                    json={"username": service.username(name),
                          "password": service.PASSWORD})
    assert r.status_code == 200, r.text
    return {"x-csrf-token": client.cookies["lp_csrf"], "Origin": ORIGIN}


def _until(get, ok):
    deadline = time.monotonic() + WAIT_S
    while not ok(got := get()):
        assert time.monotonic() < deadline, f"gave up waiting; last {got}"
        time.sleep(0.2)
    return got


def _last_stop(client):
    """The index the catalog gives the line's far stop."""
    stops = [s["id"] for s in client.get("/api/catalog").json()["stops"]]
    return stops.index(f"s{city.STOPS - 1}")


def test_health_is_public_and_says_how_to_register(client):
    r = client.get("/api/health")

    assert r.status_code == 200
    assert r.json()["registration"] == "open"


def test_the_data_needs_a_session(client):
    assert client.get("/api/catalog").status_code == 401


def test_registering_needs_the_apps_origin(client):
    r = client.post("/api/register", headers={"Origin": "https://evil.example"},
                    json={"username": "mallory", "password": service.PASSWORD})

    assert r.status_code == 403


def test_the_catalog_lists_the_citys_routes_and_stops(client):
    _signed_in(client, "catalog")

    cat = client.get("/api/catalog").json()

    assert [r["id"] for r in cat["routes"]] == [city.ROUTE]
    assert sorted(s["id"] for s in cat["stops"]) == [f"s{i}" for i in range(city.STOPS)]


def test_an_unchanged_catalog_is_revalidated_without_a_body(client):
    _signed_in(client, "etag")
    tag = client.get("/api/catalog").headers["etag"]

    r = client.get("/api/catalog", headers={"if-none-match": tag})

    assert r.status_code == 304 and not r.content


def test_the_boards_show_the_bus_coming(client, feed):
    _signed_in(client, "boards")
    last = _last_stop(client)

    due = _until(lambda: client.get(f"/api/arrivals?stops={last}").json(),
                 lambda j: j["stops"][str(last)])

    row = due["stops"][str(last)][0]
    # an untrained model times the road by its priors, not by the timetable
    assert feed.start < row["t"] <= feed.start + city.LENGTH / city.SPEED + ETA_TOL_S
    ahead = client.get(f"/api/vehicle?veh={row['veh']}").json()["stops"]
    assert ahead and all(a["route"] == row["route"] for a in ahead)


def test_an_unsafe_request_needs_the_csrf_token(client):
    headers = _signed_in(client, "csrf")

    refused = client.post("/api/logout", headers={"Origin": ORIGIN})
    taken = client.post("/api/logout", headers=headers)

    assert refused.status_code == 403
    assert taken.status_code == 200
    assert client.get("/api/catalog").status_code == 401


def test_the_socket_says_hello_then_draws_the_bus_and_its_board(client):
    _signed_in(client, "socket")
    last = _last_stop(client)

    with client.websocket_connect("/ws", headers={"Origin": ORIGIN}) as ws:
        hello = json.loads(ws.receive_text())
        assert hello["type"] == "hello" and hello["stops"] == city.STOPS
        ws.send_text(json.dumps({"type": "routes", "routes": [0]}))
        ws.send_text(json.dumps({"type": "stops", "stops": [last]}))
        frames, boards = [], []
        deadline = time.monotonic() + WAIT_S
        while not (any(len(f[2]) for f in frames)
                   and any(b[str(last)] for b in boards)):
            assert time.monotonic() < deadline
            msg = ws.receive()
            if msg.get("bytes"):
                frames.append(wire.decode(msg["bytes"]))
            elif (text := json.loads(msg["text"]))["type"] == "arrivals":
                boards.append(text["stops"])
        # the test client cancels the service the moment the block is left, which
        # races its own teardown; so the socket is closed and seen to be let go
        ws.close()
        _until(lambda: len(client.app.state.hub.clients), lambda n: n == 0)

    _, _, rows, _ = next(f for f in frames if len(f[2]))
    lat, lon = wire.latlon(rows)
    assert lat[0] == pytest.approx(city.LAT, abs=NEAR_DEG)
    assert city.LON - NEAR_DEG < lon[0] < city.LON + city.LENGTH / network.KX + NEAR_DEG


def test_a_socket_without_a_session_is_closed(client):
    with (pytest.raises(WebSocketDisconnect) as closed,
          client.websocket_connect("/ws", headers={"Origin": ORIGIN}) as ws):
        ws.receive_text()

    assert closed.value.code == 4401
