"""Operator jobs that have no business being HTTP endpoints.

An invite link is printed once and only its SHA-256 is stored, so a lost link
cannot be recovered.
"""
import asyncio
import contextlib

from . import auth, db, security, settings


def run(coro):
    return asyncio.run(coro)


@contextlib.asynccontextmanager
async def _pool(st):
    """A pool for one command, migrated and closed again."""
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
    """Erase an account; every table pointing at a user cascades. `disable` is
    the reversible one."""
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
            # a disabled account with a live session is still a live session
            await pool.execute("DELETE FROM sessions WHERE user_id = $1", uid)
            await pool.execute("DELETE FROM remember_tokens WHERE user_id = $1", uid)
            await auth.event(pool, "disabled", uid)
        return uid is not None
