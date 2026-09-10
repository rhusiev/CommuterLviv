"""Operator jobs that have no business being HTTP endpoints.

An invite link is printed once, here, on the machine that runs the service.
There is deliberately no way to ask the service for one and no way to read one
back out of the database: what it stores is a SHA-256, so a link that is lost
is gone rather than recoverable.
"""
import asyncio
import contextlib

from . import auth, db, security, settings


def run(coro):
    return asyncio.run(coro)


@contextlib.asynccontextmanager
async def _pool(st):
    """A pool for one command, migrated and closed again. Each of these runs as
    its own process, so nothing outlives the call."""
    pool = await db.connect(st.database_url, min_size=1, max_size=2)
    try:
        await db.migrate(pool)
        yield pool
    finally:
        await pool.close()


async def invite(uses=1, days=30, note=None, st=None):
    st = st or settings.load()
    async with _pool(st) as pool:
        code, hashed = security.token()
        await pool.execute(
            "INSERT INTO access_codes(code_hash, note, uses_left, expires_at) "
            "VALUES($1, $2, $3, now() + make_interval(days => $4))",
            hashed, note, uses, int(days))
        return f"{st.web_base}/join/{code}" if st.web_base else code


async def users(st=None):
    st = st or settings.load()
    async with _pool(st) as pool:
        return await pool.fetch(
            "SELECT u.username, u.created_at, u.last_login, u.disabled, "
            "u.operator, count(s.id) AS sessions FROM users u "
            "LEFT JOIN sessions s ON s.user_id = u.id AND s.expires_at > now() "
            "GROUP BY u.id ORDER BY u.created_at")


async def operator(username, on=True, st=None):
    st = st or settings.load()
    async with _pool(st) as pool:
        return await pool.fetchval(
            "UPDATE users SET operator = $2 WHERE lower(username) = $1 "
            "RETURNING id", security.clean_username(username), on) is not None


async def delete(username, st=None):
    """Erase an account and everything hanging off it.

    Every table that points at a user cascades, so this takes the sessions,
    the remember-me tokens, the preferences and the audit trail with it - there
    is nothing left to say the account existed, which is the point. `disable`
    is the reversible one.
    """
    st = st or settings.load()
    async with _pool(st) as pool:
        return await pool.fetchval(
            "DELETE FROM users WHERE lower(username) = $1 RETURNING id",
            security.clean_username(username)) is not None


async def disable(username, on=True, st=None):
    st = st or settings.load()
    async with _pool(st) as pool:
        uid = await pool.fetchval(
            "UPDATE users SET disabled = $2 WHERE lower(username) = $1 "
            "RETURNING id", security.clean_username(username), on)
        if uid and on:
            # A disabled account with a live session is still a live session
            await pool.execute("DELETE FROM sessions WHERE user_id = $1", uid)
            await pool.execute("DELETE FROM remember_tokens WHERE user_id = $1", uid)
            await auth.event(pool, "disabled", uid)
        return uid is not None
