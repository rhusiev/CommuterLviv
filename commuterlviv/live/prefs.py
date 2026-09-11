"""Named route sets, pinned stops, saved places, and which set is showing.

Routes and pins are stored as feed ids, never as catalog positions, which shift
whenever the city adds a stop, and are validated against the catalog first. A
place is a name and a point, validated only for sanity, kept in the same jsonb
as the pins.
"""
import json

from asyncpg.exceptions import UniqueViolationError

MAX_SETS = 32
MAX_ROUTES = 64
MAX_NAME = 40

MAX_PINS = 63   # one under hub.MAX_STOPS, so pins plus the open card always fit

MAX_PLACES = 24


def clean(name, routes, valid):
    """(name, routes) as they will be stored, or (None, why not)."""
    name = (name or "").strip()
    if not 1 <= len(name) <= MAX_NAME:
        return None, f"a name must be 1 to {MAX_NAME} characters"
    if not isinstance(routes, list):
        return None, "routes must be a list"
    seen = []
    for r in routes:
        if not isinstance(r, str) or r not in valid:
            return None, f"no such route: {r!r}"
        if r not in seen:
            seen.append(r)
    if len(seen) > MAX_ROUTES:
        return None, f"a set holds at most {MAX_ROUTES} routes"
    return (name, seen), None


def as_json(row):
    return {"id": str(row["id"]), "name": row["name"],
            "routes": list(row["routes"]), "ord": row["ord"]}


async def listing(pool, user_id):
    rows = await pool.fetch(
        "SELECT id, name, routes, ord FROM route_sets WHERE user_id = $1 "
        "ORDER BY ord, created_at", user_id)
    row = await pool.fetchrow(
        "SELECT active_set, data FROM user_prefs WHERE user_id = $1", user_id)
    active = row["active_set"] if row else None
    return {"sets": [as_json(r) for r in rows],
            "active": str(active) if active else None,
            "pins": _kept(row, "pins"), "places": _kept(row, "places")}


def _kept(row, key):
    """One list out of the jsonb everything small is kept in."""
    if row is None:
        return []
    data = row["data"]
    if isinstance(data, str):        # asyncpg hands back jsonb as text
        data = json.loads(data)
    kept = (data or {}).get(key)
    return kept if isinstance(kept, list) else []


async def _read(pool, user_id, key):
    return _kept(await pool.fetchrow(
        "SELECT data FROM user_prefs WHERE user_id = $1", user_id), key)


async def _write(pool, user_id, key, value):
    """The whole list, on every change, so a partial apply is impossible."""
    await pool.execute(
        "INSERT INTO user_prefs(user_id, data) "
        "VALUES($1, jsonb_build_object($2::text, $3::jsonb)) "
        "ON CONFLICT (user_id) DO UPDATE "
        "SET data = user_prefs.data || jsonb_build_object($2::text, $3::jsonb),"
        "    updated_at = now()",
        user_id, key, json.dumps(value))


async def pins(pool, user_id):
    return await _read(pool, user_id, "pins")


def clean_pins(stops, valid):
    """The pins as they will be stored, or (None, why not); unknown ids are
    dropped rather than refused."""
    if not isinstance(stops, list):
        return None, "pins must be a list"
    seen = []
    for s in stops:
        if isinstance(s, str) and s in valid and s not in seen:
            seen.append(s)
    if len(seen) > MAX_PINS:
        return None, f"at most {MAX_PINS} pinned stops"
    return seen, None


async def set_pins(pool, user_id, stops):
    await _write(pool, user_id, "pins", stops)


async def places(pool, user_id):
    return await _read(pool, user_id, "places")


def clean_places(saved):
    """The places as they will be stored, or (None, why not); the name is the
    identity, so a repeated name keeps the last one given."""
    if not isinstance(saved, list):
        return None, "places must be a list"
    seen = {}
    for p in saved:
        if not isinstance(p, dict):
            return None, "a place must be an object"
        name = (p.get("name") or "").strip()
        lat, lon = p.get("lat"), p.get("lon")
        if not 1 <= len(name) <= MAX_NAME:
            return None, f"a name must be 1 to {MAX_NAME} characters"
        if not isinstance(lat, (int, float)) or not isinstance(lon, (int, float)):
            return None, "a place needs a lat and a lon"
        if not -90 <= lat <= 90 or not -180 <= lon <= 180:
            return None, "that is not a point on the planet"
        seen[name] = {"name": name, "lat": float(lat), "lon": float(lon)}
    if len(seen) > MAX_PLACES:
        return None, f"at most {MAX_PLACES} saved places"
    return list(seen.values()), None


async def set_places(pool, user_id, saved):
    await _write(pool, user_id, "places", saved)


async def create(pool, user_id, name, routes):
    """A name clash is left to the unique index: checking first would race."""
    async with pool.acquire() as con:
        async with con.transaction():
            n = await con.fetchval(
                "SELECT count(*) FROM route_sets WHERE user_id = $1", user_id)
            if n >= MAX_SETS:
                return None, f"at most {MAX_SETS} sets"
            try:
                row = await con.fetchrow(
                    "INSERT INTO route_sets(user_id, name, routes, ord) "
                    "VALUES($1,$2,$3,$4) RETURNING id, name, routes, ord",
                    user_id, name, routes, n)
            except UniqueViolationError:
                return None, "a set with that name already exists"
    return as_json(row), None


async def update(pool, set_id, user_id, name, routes):
    try:
        row = await pool.fetchrow(
            "UPDATE route_sets SET name = $3, routes = $4, updated_at = now() "
            "WHERE id = $1 AND user_id = $2 RETURNING id, name, routes, ord",
            set_id, user_id, name, routes)
    except UniqueViolationError:
        return None, "a set with that name already exists"
    return (as_json(row), None) if row else (None, "no such set")


async def delete(pool, set_id, user_id):
    return await pool.fetchval(
        "DELETE FROM route_sets WHERE id = $1 AND user_id = $2 RETURNING id",
        set_id, user_id) is not None


async def activate(pool, user_id, set_id):
    """Which set the map is showing. Null clears it."""
    if set_id is not None and not await pool.fetchval(
            "SELECT 1 FROM route_sets WHERE id = $1 AND user_id = $2",
            set_id, user_id):
        return False
    await pool.execute(
        "INSERT INTO user_prefs(user_id, active_set) VALUES($1,$2) "
        "ON CONFLICT (user_id) DO UPDATE SET active_set = $2, updated_at = now()",
        user_id, set_id)
    return True
