"""Named route sets, pinned stops, and which set is showing.

A set is a list of route ids - "the four routes I watch from the office" - and
the point of keeping them here rather than in the browser is that the same four
routes are the ones wanted on the phone at the stop. Pins are here for the same
reason, and were in each device's own storage until 2026-09-08.

Both are stored as feed ids, never as catalog positions. A position is only
meaningful against the catalog that produced it: the city adds a stop, every
index after it shifts, and a pin that was Енергетична silently becomes the next
stop along with nothing to show for it. Ids are also validated against the
catalog before they are stored, so neither can accumulate names of things the
city stopped running.
"""
import json

from asyncpg.exceptions import UniqueViolationError

MAX_SETS = 32
MAX_ROUTES = 64
MAX_NAME = 40

# One less than the 64 stops a client may watch at once (`hub.MAX_STOPS`), so
# the pins plus whichever card is open always fit
MAX_PINS = 63


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
            "pins": _pins(row)}


def _pins(row):
    if row is None:
        return []
    data = row["data"]
    if isinstance(data, str):        # asyncpg hands back jsonb as text
        data = json.loads(data)
    pins = (data or {}).get("pins")
    return pins if isinstance(pins, list) else []


async def pins(pool, user_id):
    return _pins(await pool.fetchrow(
        "SELECT data FROM user_prefs WHERE user_id = $1", user_id))


def clean_pins(stops, valid):
    """The pins as they will be stored, or (None, why not).

    Unknown ids are dropped rather than refused: a client that has been away
    while the feed changed should lose the stop that went away and keep the
    rest, and there is nothing the person could do about it either way.
    """
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
    await pool.execute(
        "INSERT INTO user_prefs(user_id, data) "
        "VALUES($1, jsonb_build_object('pins', $2::jsonb)) "
        "ON CONFLICT (user_id) DO UPDATE "
        "SET data = user_prefs.data || jsonb_build_object('pins', $2::jsonb), "
        "    updated_at = now()",
        user_id, json.dumps(stops))


async def create(pool, user_id, name, routes):
    async with pool.acquire() as con:
        async with con.transaction():
            n = await con.fetchval(
                "SELECT count(*) FROM route_sets WHERE user_id = $1", user_id)
            if n >= MAX_SETS:
                return None, f"at most {MAX_SETS} sets"
            clash = await con.fetchval(
                "SELECT 1 FROM route_sets WHERE user_id = $1 AND lower(name) = lower($2)",
                user_id, name)
            if clash:
                return None, "a set with that name already exists"
            row = await con.fetchrow(
                "INSERT INTO route_sets(user_id, name, routes, ord) "
                "VALUES($1,$2,$3,$4) RETURNING id, name, routes, ord",
                user_id, name, routes, n)
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


async def reorder(pool, user_id, ids):
    async with pool.acquire() as con:
        async with con.transaction():
            for i, sid in enumerate(ids):
                await con.execute(
                    "UPDATE route_sets SET ord = $3 WHERE id = $1 AND user_id = $2",
                    sid, user_id, i)
