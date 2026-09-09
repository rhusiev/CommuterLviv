"""Accounts, sessions and remember-me, against Postgres.

The session is opaque and server-side: the cookie is 32 random bytes and every
fact about the session - who it is, when it dies, what its CSRF token is - is a
row here. Nothing is signed into the cookie, so revoking a session is a DELETE
and there is no signing key to leak or rotate.

Remember-me is the classic series-and-token scheme, with the two things it is
usually shipped without. Comparisons are constant-time. And a token that has
already been spent coming back is treated as theft: the browser that presented
it either is the thief or has been robbed, and either way both copies of the
cookie have to stop working, so the series is deleted and every session the
user has is dropped with it.
"""
import datetime

from . import security

GRACE = 30.0     # s an already-rotated remember-me token stays acceptable


def _now():
    return datetime.datetime.now(datetime.timezone.utc)


def _delta(seconds):
    return datetime.timedelta(seconds=seconds)


async def event(pool, kind, user_id=None, ip=None, detail=None):
    await pool.execute(
        "INSERT INTO auth_events(kind, user_id, ip, detail) VALUES($1,$2,$3,$4)",
        kind, user_id, ip, detail)


async def user_count(pool):
    return await pool.fetchval("SELECT count(*) FROM users")


async def register(pool, ph, username, password, code=None, mode="code"):
    """Create an account. Returns (user_id, None) or (None, why not).

    The invite code is spent in the same transaction as the insert, so two
    registrations racing on a one-use code cannot both win.
    """
    name = security.clean_username(username)
    if name is None:
        return None, "username must be 3-32 characters of a-z, 0-9, dot, dash or underscore"
    why = security.check_password(password, name)
    if why:
        return None, why
    if mode == "closed":
        return None, "registration is closed"

    hashed = ph.hash(password)
    async with pool.acquire() as con:
        async with con.transaction():
            if mode == "code":
                spent = await con.fetchval(
                    "UPDATE access_codes SET uses_left = uses_left - 1 "
                    "WHERE code_hash = $1 AND uses_left > 0 "
                    "AND (expires_at IS NULL OR expires_at > now()) "
                    "RETURNING code_hash", security.digest(code or ""))
                if spent is None:
                    return None, "that invite code is not valid"
            taken = await con.fetchval(
                "SELECT 1 FROM users WHERE lower(username) = $1", name)
            if taken:
                return None, "that username is taken"
            uid = await con.fetchval(
                "INSERT INTO users(username, password_hash) VALUES($1,$2) "
                "RETURNING id", name, hashed)
    return uid, None


async def login(pool, ph, username, password):
    """The user, or None. Costs the same either way: a username that does not
    exist still pays for one argon2 verify, so the response time does not say
    which accounts are real."""
    name = security.clean_username(username)
    row = None if name is None else await pool.fetchrow(
        "SELECT id, password_hash, disabled FROM users WHERE lower(username) = $1",
        name)
    if row is None:
        security.burn(ph)
        return None
    ok, rehash = security.verify(ph, row["password_hash"], password)
    if not ok or row["disabled"]:
        return None
    if rehash:
        await pool.execute("UPDATE users SET password_hash = $2 WHERE id = $1",
                           row["id"], ph.hash(password))
    await pool.execute("UPDATE users SET last_login = now() WHERE id = $1", row["id"])
    return row["id"]


async def change_password(pool, ph, user_id, old, new, keep_session=None):
    """Returns None on success, otherwise why not. Every other session and every
    remember-me cookie dies here: changing a password is what someone does when
    they think they have been compromised, and it has to mean it."""
    stored = await pool.fetchval("SELECT password_hash FROM users WHERE id = $1",
                                 user_id)
    if stored is None:
        return "no such user"
    ok, _ = security.verify(ph, stored, old)
    if not ok:
        return "the current password is wrong"
    why = security.check_password(new)
    if why:
        return why
    async with pool.acquire() as con:
        async with con.transaction():
            await con.execute("UPDATE users SET password_hash = $2 WHERE id = $1",
                              user_id, ph.hash(new))
            await con.execute("DELETE FROM remember_tokens WHERE user_id = $1",
                              user_id)
            await con.execute(
                "DELETE FROM sessions WHERE user_id = $1 AND id <> $2",
                user_id, keep_session or b"")
    return None


async def new_session(pool, user_id, idle, max_life, ip=None, agent=None):
    """A fresh session. Returns (cookie value, csrf token, expiry)."""
    raw, hashed = security.token()
    csrf_raw, csrf_hash = security.token()
    expires = _now() + _delta(min(idle, max_life))
    await pool.execute(
        "INSERT INTO sessions(id, user_id, csrf, expires_at, ip, user_agent) "
        "VALUES($1,$2,$3,$4,$5,$6)",
        hashed, user_id, csrf_hash, expires, ip, (agent or "")[:300])
    return raw, csrf_raw, expires


async def load_session(pool, raw, idle, max_life, touch=True):
    """The session behind a cookie, or None.

    Two expiries, both enforced here rather than by the cookie: the cookie is a
    client's copy of when it should stop trying, and a client is free to lie.
    Idle expiry is refreshed at most once a minute, so an open map tab does not
    write a row per frame - and not at all when `touch` is false, which is how
    a background check asks whether a session is still good without being the
    reason it stays that way.
    """
    if not raw:
        return None
    row = await pool.fetchrow(
        "SELECT s.id, s.user_id, s.csrf, s.created_at, s.last_seen, u.username, "
        "u.disabled FROM sessions s JOIN users u ON u.id = s.user_id "
        "WHERE s.id = $1 AND s.expires_at > now()", security.digest(raw))
    if row is None or row["disabled"]:
        return None
    now = _now()
    if now - row["created_at"] > _delta(max_life):
        await pool.execute("DELETE FROM sessions WHERE id = $1", row["id"])
        return None
    if touch and now - row["last_seen"] > _delta(60):
        await pool.execute(
            "UPDATE sessions SET last_seen = now(), expires_at = $2 WHERE id = $1",
            row["id"], min(now + _delta(idle), row["created_at"] + _delta(max_life)))
    return row


async def drop_session(pool, raw):
    if raw:
        await pool.execute("DELETE FROM sessions WHERE id = $1",
                           security.digest(raw))


async def issue_remember(pool, user_id, days, ip=None, agent=None):
    series_raw, series = security.token()
    token_raw, token_hash = security.token()
    await pool.execute(
        "INSERT INTO remember_tokens(series, user_id, token_hash, expires_at, "
        "ip, user_agent) VALUES($1,$2,$3,$4,$5,$6)",
        series, user_id, token_hash, _now() + _delta(days * 86400), ip,
        (agent or "")[:300])
    return f"{series_raw}.{token_raw}"


async def consume_remember(pool, raw, days, ip=None):
    """Trade a remember-me cookie for the user it names and a new cookie.

    Returns (user_id, new cookie) on success, (None, None) when the cookie is
    simply unknown or expired, and (None, "theft") when a spent token comes
    back - which is the one case that costs the user every session they have.
    """
    series_raw, _, token_raw = (raw or "").partition(".")
    if not series_raw or not token_raw:
        return None, None
    series = security.digest(series_raw)
    presented = security.digest(token_raw)

    async with pool.acquire() as con:
        async with con.transaction():
            row = await con.fetchrow(
                "SELECT user_id, token_hash, prev_hash, rotated_at FROM "
                "remember_tokens WHERE series = $1 AND expires_at > now() "
                "FOR UPDATE", series)
            if row is None:
                return None, None
            if security.same(row["token_hash"], presented):
                pass
            elif (row["prev_hash"] and row["rotated_at"]
                  and security.same(row["prev_hash"], presented)
                  and (_now() - row["rotated_at"]).total_seconds() < GRACE):
                # Two tabs woke up together; the loser of the race is not a thief
                return row["user_id"], None
            else:
                await con.execute("DELETE FROM remember_tokens WHERE user_id = $1",
                                  row["user_id"])
                await con.execute("DELETE FROM sessions WHERE user_id = $1",
                                  row["user_id"])
                await con.execute(
                    "INSERT INTO auth_events(kind, user_id, ip, detail) "
                    "VALUES('remember_theft', $1, $2, 'spent token replayed')",
                    row["user_id"], ip)
                return None, "theft"

            fresh_raw, fresh_hash = security.token()
            await con.execute(
                "UPDATE remember_tokens SET token_hash = $2, prev_hash = $3, "
                "rotated_at = now(), last_used_at = now(), expires_at = $4 "
                "WHERE series = $1",
                series, fresh_hash, row["token_hash"],
                _now() + _delta(days * 86400))
    return row["user_id"], f"{series_raw}.{fresh_raw}"


async def forget_remember(pool, raw):
    series_raw, _, _ = (raw or "").partition(".")
    if series_raw:
        await pool.execute("DELETE FROM remember_tokens WHERE series = $1",
                           security.digest(series_raw))


async def sweep(pool):
    """Delete what has expired. Nothing depends on this for correctness - every
    read already filters on the expiry - it just keeps the tables small."""
    async with pool.acquire() as con:
        await con.execute("DELETE FROM sessions WHERE expires_at < now()")
        await con.execute("DELETE FROM remember_tokens WHERE expires_at < now()")
        await con.execute("DELETE FROM auth_events WHERE at < now() - interval '90 days'")
