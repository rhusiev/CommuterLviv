"""The HTTP and websocket surface.

Every request goes through four rules in order: who the caller is (rule 1,
session or remember-me cookie), whether they meant to make it (rule 2, Origin
plus an echoed CSRF token), how often they are asking (rule 3, token buckets),
and only then the work.
"""
import asyncio
import contextlib
import ipaddress
import json
import time
import uuid as uuidlib

from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.middleware.gzip import GZipMiddleware
from starlette.responses import JSONResponse, Response
from starlette.routing import Route, WebSocketRoute
from starlette.websockets import WebSocketDisconnect

from .. import __version__, network
from . import (auth, db, geometry, hub, journeys, prefs, security, service,
               settings, state)

SESSION_COOKIE = "lp_sess"
CSRF_COOKIE = "lp_csrf"
REMEMBER_COOKIE = "lp_remember"

MAX_BODY = 8 * 1024
SESSION_RECHECK = 60.0          # s between asking whether an open socket still has a session
PLAN_WORKERS = 4                # journey searches running at once, city-wide


def _address(raw):
    """The header as an address, or None. `auth_events.ip` is an `inet` column,
    so a non-address would make the insert on the login path raise."""
    try:
        return str(ipaddress.ip_address(raw))
    except ValueError:
        return None


def log(*a):
    print(time.strftime("%Y-%m-%d %H:%M:%S"), *a, flush=True)


class Guard:
    """Rules 2 and 3, and the cookies rule 1 rides on."""

    def __init__(self, st):
        self.set = st
        self.prefix = "__Host-" if st.secure_cookies else ""
        self.auth_ip = security.Bucket(per_minute=20, burst=20)
        self.auth_user = security.Bucket(per_minute=5, burst=5)
        self.api = security.Bucket(per_minute=600, burst=200)
        self.socket = security.Bucket(per_minute=60, burst=20)

    def name(self, base):
        return self.prefix + base

    def ip(self, request):
        """The caller's address; `X-Forwarded-For` is read only when the
        deployment says a proxy rewrites it."""
        if self.set.trust_proxy:
            fwd = request.headers.get("x-forwarded-for", "")
            if fwd:
                return _address(fwd.split(",")[0].strip())
        return request.client.host if request.client else None

    def origin_ok(self, request):
        """An unsafe request must come from an origin we serve; the CSRF token
        is the second lock, for proxies that strip the header."""
        origin = request.headers.get("origin")
        if origin is None:
            # not a browser fetch: a same-origin fetch always sends one
            return self.set.dev
        return origin in self.set.origins

    def csrf_ok(self, request, session):
        token = request.headers.get("x-csrf-token", "")
        return bool(token) and security.same(security.digest(token),
                                             session["csrf"])

    def set_session(self, resp, raw, csrf, max_age):
        resp.set_cookie(self.name(SESSION_COOKIE), raw, max_age=int(max_age),
                        path="/", httponly=True, samesite="lax",
                        secure=self.set.secure_cookies)
        # readable by our own scripts on purpose: they echo it back in a header,
        # which a cross-site page cannot do
        resp.set_cookie(self.name(CSRF_COOKIE), csrf, max_age=int(max_age),
                        path="/", httponly=False, samesite="lax",
                        secure=self.set.secure_cookies)

    def set_remember(self, resp, raw):
        resp.set_cookie(self.name(REMEMBER_COOKIE), raw,
                        max_age=int(self.set.remember_days * 86400), path="/",
                        httponly=True, samesite="lax",
                        secure=self.set.secure_cookies)

    def clear(self, resp):
        for base in (SESSION_COOKIE, CSRF_COOKIE, REMEMBER_COOKIE):
            resp.delete_cookie(self.name(base), path="/",
                               secure=self.set.secure_cookies, samesite="lax")


def error(message, status=400, **extra):
    return JSONResponse({"error": message, **extra}, status_code=status)


async def body(request):
    # checked before reading: buffering first would already cost the memory
    declared = request.headers.get("content-length", "")
    if declared.isdigit() and (len(declared) > 9 or int(declared) > MAX_BODY):
        return None, error("request too large", 413)
    raw = b""
    async for chunk in request.stream():
        raw += chunk
        if len(raw) > MAX_BODY:
            return None, error("request too large", 413)
    try:
        data = json.loads(raw or b"{}")
    except json.JSONDecodeError:
        return None, error("expected JSON")
    return (data, None) if isinstance(data, dict) else (None, error("expected an object"))


async def resolve(request):
    """Rule 1: the session row, creating one from a remember-me cookie if that
    is all the caller has."""
    app = request.app.state
    g, st = app.guard, app.settings
    raw = request.cookies.get(g.name(SESSION_COOKIE))
    row = await auth.load_session(app.pool, raw, st.session_idle, st.session_max)
    if row is not None:
        return row, None

    remembered = request.cookies.get(g.name(REMEMBER_COOKIE))
    if not remembered:
        return None, None
    uid, replacement = await auth.consume_remember(
        app.pool, remembered, st.remember_days, g.ip(request))
    if uid is None:
        return None, "theft" if replacement == "theft" else None
    sess_raw, csrf, expires = await auth.new_session(
        app.pool, uid, st.session_idle, st.session_max, g.ip(request),
        request.headers.get("user-agent"))
    row = await auth.load_session(app.pool, sess_raw, st.session_idle,
                                  st.session_max)
    await auth.event(app.pool, "remember_used", uid, g.ip(request))
    return row, ("issue", sess_raw, csrf, replacement)


def apply_issue(resp, guard, issue, st):
    if issue and issue[0] == "issue":
        _, sess_raw, csrf, replacement = issue
        guard.set_session(resp, sess_raw, csrf, st.session_idle)
        if replacement:
            guard.set_remember(resp, replacement)


def protected(handler, unsafe=True):
    """Wrap a handler in rules 1-3."""
    async def inner(request):
        app = request.app.state
        g = app.guard
        if not g.api.take(g.ip(request)):
            return error("slow down", 429)
        session, issue = await resolve(request)
        if issue == "theft":
            resp = error("this session was ended for safety; sign in again", 401)
            g.clear(resp)
            return resp
        if session is None:
            return error("sign in", 401)
        if unsafe and request.method not in ("GET", "HEAD"):
            if not g.origin_ok(request):
                return error("bad origin", 403)
            if not g.csrf_ok(request, session):
                return error("bad csrf token", 403)
        resp = await handler(request, session)
        apply_issue(resp, g, issue, app.settings)
        return resp
    return inner


async def me(request, session):
    app = request.app.state
    return JSONResponse({"username": session["username"],
                         "sets": await prefs.listing(app.pool, session["user_id"])})


async def register(request):
    app = request.app.state
    g, st = app.guard, app.settings
    if not g.origin_ok(request):
        return error("bad origin", 403)
    if not g.auth_ip.take(g.ip(request)):
        return error("too many attempts", 429,
                     retry=round(g.auth_ip.retry_after(g.ip(request))))
    data, bad = await body(request)
    if bad:
        return bad
    # the code may arrive in the path, since what an admin hands out is a link
    code = request.path_params.get("code") or data.get("code")
    uid, why = await auth.register(app.pool, app.hasher, data.get("username"),
                                   data.get("password"), code, st.registration)
    if uid is None:
        await auth.event(app.pool, "register_failed", None, g.ip(request), why)
        return error(why, 400)
    await auth.event(app.pool, "register", uid, g.ip(request))
    return await _sign_in(request, uid, bool(data.get("remember")))


async def login(request):
    app = request.app.state
    g = app.guard
    if not g.origin_ok(request):
        return error("bad origin", 403)
    ip = g.ip(request)
    data, bad = await body(request)
    if bad:
        return bad
    name = security.clean_username(data.get("username")) or "?"
    if not g.auth_ip.take(ip) or not g.auth_user.take((ip, name)):
        return error("too many attempts", 429,
                     retry=round(g.auth_ip.retry_after(ip)))
    uid = await auth.login(app.pool, app.hasher, data.get("username"),
                           data.get("password"))
    if uid is None:
        await auth.event(app.pool, "login_failed", None, ip, name)
        return error("wrong username or password", 401)
    await auth.event(app.pool, "login", uid, ip)
    return await _sign_in(request, uid, bool(data.get("remember")))


async def _sign_in(request, uid, remember):
    app = request.app.state
    g, st = app.guard, app.settings
    raw, csrf, _ = await auth.new_session(
        app.pool, uid, st.session_idle, st.session_max, g.ip(request),
        request.headers.get("user-agent"))
    resp = JSONResponse({"ok": True,
                         "sets": await prefs.listing(app.pool, uid)})
    g.set_session(resp, raw, csrf, st.session_idle)
    if remember:
        g.set_remember(resp, await auth.issue_remember(
            app.pool, uid, st.remember_days, g.ip(request),
            request.headers.get("user-agent")))
    return resp


async def logout(request, session):
    app = request.app.state
    await auth.drop_session(app.pool, request.cookies.get(
        app.guard.name(SESSION_COOKIE)))
    await auth.forget_remember(app.pool, request.cookies.get(
        app.guard.name(REMEMBER_COOKIE)))
    resp = JSONResponse({"ok": True})
    app.guard.clear(resp)
    return resp


async def password(request, session):
    app = request.app.state
    data, bad = await body(request)
    if bad:
        return bad
    why = await auth.change_password(app.pool, app.hasher, session["user_id"],
                                     data.get("old"), data.get("new"),
                                     session["id"])
    if why:
        return error(why, 400)
    await auth.event(app.pool, "password_changed", session["user_id"],
                     app.guard.ip(request))
    resp = JSONResponse({"ok": True})
    resp.delete_cookie(app.guard.name(REMEMBER_COOKIE), path="/",
                       secure=app.settings.secure_cookies, samesite="lax")
    return resp


async def catalog(request, session):
    """Routes and stops: large, unchanging, cached by the client against the ETag."""
    app = request.app.state
    if request.headers.get("if-none-match") == app.catalog_tag:
        return Response(status_code=304, headers={"ETag": app.catalog_tag})
    return Response(app.catalog_json, media_type="application/json",
                    headers={"ETag": app.catalog_tag,
                             "Cache-Control": "private, max-age=86400"})


async def shapes(request, session):
    """Where every route physically goes, and which way; a separate request from
    the catalog because only some views need this half megabyte."""
    app = request.app.state
    if request.headers.get("if-none-match") == app.shapes_tag:
        return Response(status_code=304, headers={"ETag": app.shapes_tag})
    return Response(app.shapes_json, media_type="application/json",
                    headers={"ETag": app.shapes_tag,
                             "Cache-Control": "private, max-age=86400"})


async def arrivals(request, session):
    """The timetable tab: what is coming to these stops, soonest first."""
    app = request.app.state
    want = request.query_params.get("stops", "")
    cat = app.svc.live.cat
    # `int` raises on a long enough digit string, and the query is unbounded
    ids = [int(p) for p in want.split(",")[:hub.MAX_STOPS]
           if p.isdigit() and len(p) <= 9 and int(p) < len(cat.stops)]
    return JSONResponse(hub.due(app.svc.live.arrivals, ids))


async def vehicle(request, session):
    """One vehicle's predicted stops and times; an untracked id gets an empty
    list rather than a 404."""
    app = request.app.state
    want = request.query_params.get("veh", "")
    if not want.isdigit() or len(want) > 9:
        return error("veh must be a number")
    arr = app.svc.live.arrivals
    rows = arr.of(int(want))
    return JSONResponse({"t": arr.t, "veh": int(want), "stops": [
        {"stop": int(r["stop"]), "route": int(r["route"]), "t": int(r["t"])}
        for r in rows]})


def _point(raw):
    """A "lat,lon" query parameter, or None; points outside the city's box are
    refused, since the footpath graph stops at the city limit."""
    parts = (raw or "").split(",")
    if len(parts) != 2:
        return None
    try:
        lat, lon = float(parts[0]), float(parts[1])
    except ValueError:
        return None
    if not (49.7 <= lat <= 50.05 and 23.8 <= lon <= 24.25):
        return None
    return lat, lon


async def journey(request, session):
    """Door to door, ranked by arrival; each leg says whether it came from a
    tracked vehicle or from the timetable."""
    app = request.app.state
    if app.planner is None:
        return error("this service has no journey planner", status=503)
    origin = _point(request.query_params.get("from"))
    dest = _point(request.query_params.get("to"))
    if origin is None or dest is None:
        return error("from and to must each be lat,lon inside Lviv")
    # refused rather than queued when every worker is busy: a queue of
    # second-long searches is a denial of service with a longer fuse
    if app.planning.locked():
        return error("the planner is busy; try that again", 503)
    async with app.planning:
        found = await asyncio.to_thread(app.planner.search, origin, dest,
                                        app.svc.live.arrivals)
    return JSONResponse(found)


async def pins(request, session):
    """The stops someone watches, by feed id; the whole list is written on
    every change."""
    app = request.app.state
    uid = session["user_id"]
    if request.method == "GET":
        return JSONResponse({"pins": await prefs.pins(app.pool, uid)})
    data, bad = await body(request)
    if bad:
        return bad
    stops, why = prefs.clean_pins(data.get("pins"), app.svc.live.cat.stop_i)
    if why:
        return error(why)
    await prefs.set_pins(app.pool, uid, stops)
    return JSONResponse({"pins": stops})


async def places(request, session):
    """Saved places, as the journey planner's ends; written whole on every change."""
    app = request.app.state
    uid = session["user_id"]
    if request.method == "GET":
        return JSONResponse({"places": await prefs.places(app.pool, uid)})
    data, bad = await body(request)
    if bad:
        return bad
    saved, why = prefs.clean_places(data.get("places"))
    if why:
        return error(why)
    await prefs.set_places(app.pool, uid, saved)
    return JSONResponse({"places": saved})


async def sets(request, session):
    app = request.app.state
    uid = session["user_id"]
    if request.method == "GET":
        return JSONResponse(await prefs.listing(app.pool, uid))
    data, bad = await body(request)
    if bad:
        return bad
    valid = app.svc.live.cat.route_i
    ok, why = prefs.clean(data.get("name"), data.get("routes") or [], valid)
    if why:
        return error(why)
    row, why = await prefs.create(app.pool, uid, *ok)
    return error(why) if why else JSONResponse(row, status_code=201)


async def one_set(request, session):
    app = request.app.state
    uid, sid = session["user_id"], request.path_params["sid"]
    if request.method == "DELETE":
        return (JSONResponse({"ok": True}) if await prefs.delete(app.pool, sid, uid)
                else error("no such set", 404))
    data, bad = await body(request)
    if bad:
        return bad
    ok, why = prefs.clean(data.get("name"), data.get("routes") or [],
                          app.svc.live.cat.route_i)
    if why:
        return error(why)
    row, why = await prefs.update(app.pool, sid, uid, *ok)
    return error(why, 404 if why == "no such set" else 400) if why \
        else JSONResponse(row)


async def active(request, session):
    app = request.app.state
    data, bad = await body(request)
    if bad:
        return bad
    sid = data.get("id")
    try:
        sid = uuidlib.UUID(sid) if sid else None
    except (ValueError, AttributeError, TypeError):
        return error("no such set", 404)
    if not await prefs.activate(app.pool, session["user_id"], sid):
        return error("no such set", 404)
    return JSONResponse({"ok": True})


async def health(request):
    """Public and deliberately thin; `registration` and `tiles` are here
    because a client needs both before anyone is signed in."""
    app = request.app.state
    return JSONResponse({"ok": app.svc.live.epochs > 0 or app.svc.polls > 0,
                         "uptime": round(time.time() - app.started, 1),
                         "version": __version__,
                         "registration": app.settings.registration,
                         "tiles": app.settings.self_tiles})


async def status(request, session):
    """Engine health and socket counts; operators only
    (`python -m commuterlviv admin operator <name>` grants it)."""
    if not session["operator"]:
        return error("not found", 404)
    app = request.app.state
    return JSONResponse({**app.svc.health(), **app.hub.stats()})


async def socket(ws):
    """The live map. Same session cookie as everything else, plus an Origin
    check: a websocket handshake is not covered by the same-origin policy."""
    app = ws.app.state
    g = app.guard
    if not g.socket.take(g.ip(ws)):
        await ws.close(code=1013)
        return
    origin = ws.headers.get("origin")
    if origin not in app.settings.origins and not app.settings.dev:
        await ws.close(code=1008)
        return
    raw = ws.cookies.get(g.name(SESSION_COOKIE))
    session = await auth.load_session(
        app.pool, raw, app.settings.session_idle, app.settings.session_max)
    if session is None:
        await ws.close(code=4401)
        return
    await ws.accept()
    watch = asyncio.create_task(expire(ws, app, raw))
    try:
        with contextlib.suppress(WebSocketDisconnect):
            await app.hub.serve(ws, session["user_id"])
    finally:
        watch.cancel()
        await asyncio.gather(watch, return_exceptions=True)


async def expire(ws, app, raw):
    """Close a socket whose session has ended: the handshake is the only place
    a websocket is authenticated. Read with `touch=False`, so an idle tab does
    not keep itself signed in."""
    while True:
        await asyncio.sleep(SESSION_RECHECK)
        alive = await auth.load_session(app.pool, raw, app.settings.session_idle,
                                        app.settings.session_max, touch=False)
        if alive is None:
            with contextlib.suppress(RuntimeError):
                await ws.close(code=4401)
            return


def routes():
    return [
        Route("/api/register", register, methods=["POST"]),
        Route("/api/register/{code}", register, methods=["POST"]),
        Route("/api/login", login, methods=["POST"]),
        Route("/api/logout", protected(logout), methods=["POST"]),
        Route("/api/password", protected(password), methods=["POST"]),
        Route("/api/me", protected(me), methods=["GET"]),
        Route("/api/catalog", protected(catalog), methods=["GET"]),
        Route("/api/shapes", protected(shapes), methods=["GET"]),
        Route("/api/arrivals", protected(arrivals), methods=["GET"]),
        Route("/api/vehicle", protected(vehicle), methods=["GET"]),
        Route("/api/plan", protected(journey), methods=["GET"]),
        Route("/api/pins", protected(pins), methods=["GET", "POST"]),
        Route("/api/places", protected(places), methods=["GET", "POST"]),
        Route("/api/sets", protected(sets), methods=["GET", "POST"]),
        Route("/api/sets/active", protected(active), methods=["POST"]),
        Route("/api/sets/{sid:uuid}", protected(one_set),
              methods=["PUT", "DELETE"]),
        Route("/api/status", protected(status), methods=["GET"]),
        Route("/api/health", health, methods=["GET"]),
        WebSocketRoute("/ws", socket),
    ]


def build(st=None, net=None):
    st = st or settings.load()

    @contextlib.asynccontextmanager
    async def lifespan(app):
        s = app.state
        s.settings = st
        s.started = time.time()
        s.guard = Guard(st)
        s.hasher = security.hasher(**st.argon2)
        s.pool = await db.connect(st.database_url)
        await db.migrate(s.pool, log)
        loaded = net if net is not None else network.load()
        cat = state.Catalog(loaded)
        s.catalog_json = json.dumps(cat.describe()).encode()
        s.catalog_tag = f'W/"{len(s.catalog_json):x}-{len(cat.stops):x}"'
        # seconds of projection and thinning, once, rather than per client
        s.shapes_json = json.dumps(
            geometry.describe(loaded, cat.routes)).encode()
        s.shapes_tag = f'W/"{len(s.shapes_json):x}-{len(cat.routes):x}"'
        s.svc = service.Service(st, loaded, cat, log)
        s.planner = journeys.Planner.maybe(loaded, cat, log)
        s.hub = hub.Hub(s.svc.live)
        s.planning = asyncio.Semaphore(PLAN_WORKERS)
        s.tasks = [*await s.svc.start(s.hub), asyncio.create_task(sweeper(s.pool))]
        if s.planner is None and st.build_planner:
            s.tasks.append(asyncio.create_task(
                journeys.arrange(s, loaded, cat, log)))
        log(f"serving {st.variant} on {len(cat.routes)} routes, "
            f"{len(cat.stops)} stops")
        try:
            yield
        finally:
            for t in s.tasks:
                t.cancel()
            await asyncio.gather(*s.tasks, return_exceptions=True)
            await s.pool.close()

    # gzip only ever sees complete HTTP responses; the websocket's packed bytes
    # are untouched
    return Starlette(routes=routes(), lifespan=lifespan,
                     middleware=[Middleware(GZipMiddleware, minimum_size=1024)])


async def sweeper(pool, every=3600.0):
    while True:
        await asyncio.sleep(every)
        try:
            await auth.sweep(pool)
        except Exception as exc:
            log("sweep failed", repr(exc)[:200])
