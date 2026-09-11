"""Passwords, opaque tokens, and how often one address may try.

Secrets come from the OS, are stored as their SHA-256, and are compared with
`hmac.compare_digest` rather than `==`, which leaks a prefix length by timing.
"""
import hashlib
import hmac
import re
import secrets
import time
import unicodedata

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError

TOKEN_BYTES = 32
MIN_PASSWORD = 10
MAX_PASSWORD = 128           # argon2 is slow: a client must not pick how slow
USERNAME = re.compile(r"^[a-z0-9](?:[a-z0-9._-]{1,30}[a-z0-9])$")

# burned when a username does not exist, so a miss costs the same as a hit
_DUMMY = None


def hasher(**kw):
    return PasswordHasher(**kw)


def token():
    """A new secret, and the form of it that gets stored."""
    raw = secrets.token_urlsafe(TOKEN_BYTES)
    return raw, digest(raw)


def digest(raw):
    return hashlib.sha256(raw.encode()).digest()


def same(a, b):
    return hmac.compare_digest(a, b)


def verify(ph, stored, password):
    """Whether the password matches, and whether the stored hash wants rehashing
    because the cost parameters have since been raised."""
    try:
        ph.verify(stored, password)
    except (VerifyMismatchError, InvalidHashError):
        return False, False
    return True, ph.check_needs_rehash(stored)


def burn(ph):
    """Spend the same work a real verify would, for a nonexistent username."""
    global _DUMMY
    if _DUMMY is None:
        _DUMMY = ph.hash("dummy password, never accepted")
    try:
        ph.verify(_DUMMY, "not the dummy password")
    except (VerifyMismatchError, InvalidHashError):
        pass


def clean_username(name):
    """The canonical form, or None if it is not a username; NFKC-normalised,
    so two names that render identically cannot both exist."""
    name = unicodedata.normalize("NFKC", (name or "").strip()).lower()
    return name if USERNAME.match(name) else None


def check_password(password, username=None):
    """None if it will do, otherwise why not."""
    if not isinstance(password, str) or not MIN_PASSWORD <= len(password) <= MAX_PASSWORD:
        return f"password must be between {MIN_PASSWORD} and {MAX_PASSWORD} characters"
    if username and username in password.lower():
        return "password must not contain the username"
    if len(set(password)) < 5:
        return "password is too repetitive"
    return None


class Bucket:
    """A per-key token bucket, swept lazily and refilled continuously.
    In-process only: behind several processes it must become a shared counter."""

    __slots__ = ("rate", "burst", "seen", "sweep_at")

    def __init__(self, per_minute, burst):
        self.rate = per_minute / 60.0
        self.burst = float(burst)
        self.seen = {}
        self.sweep_at = time.monotonic()

    def take(self, key, cost=1.0):
        """True if the request may proceed."""
        now = time.monotonic()
        if now - self.sweep_at > 300.0:
            self._sweep(now)
        tokens, at = self.seen.get(key, (self.burst, now))
        tokens = min(self.burst, tokens + (now - at) * self.rate)
        if tokens < cost:
            self.seen[key] = (tokens, now)
            return False
        self.seen[key] = (tokens - cost, now)
        return True

    def retry_after(self, key, cost=1.0):
        tokens, at = self.seen.get(key, (self.burst, time.monotonic()))
        return max(0.0, (cost - tokens) / self.rate)

    def _sweep(self, now):
        self.seen = {k: v for k, v in self.seen.items()
                     if v[0] < self.burst or now - v[1] < 300.0}
        self.sweep_at = now
