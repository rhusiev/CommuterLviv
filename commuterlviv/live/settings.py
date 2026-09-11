"""Everything the service reads from its environment; no default here is unsafe
in production."""
import os
from dataclasses import dataclass, field

from .. import config

ENV = "COMMUTERLVIV_"


def _env(name, default=None):
    v = os.environ.get(ENV + name, default)
    if v is None:
        raise RuntimeError(f"{ENV + name} is not set")
    return v


def _flag(name, default):
    v = os.environ.get(ENV + name)
    if v is None:
        return default
    if v.lower() not in ("0", "1", "true", "false"):
        raise RuntimeError(f"{ENV + name} must be true or false, got {v!r}")
    return v.lower() in ("1", "true")


@dataclass(frozen=True)
class Settings:
    database_url: str
    variant: str                 # which predictor serves the public numbers
    secure_cookies: bool
    origins: tuple[str, ...]     # exact origins allowed to make unsafe requests
    web_base: str                # where the web app lives, for invite links
    registration: str            # open | code | closed
    session_idle: float          # s of inactivity before a session dies
    session_max: float           # s a session lives however active
    remember_days: float
    trust_proxy: bool            # whether X-Forwarded-For may name the client
    build_planner: bool          # fetch the footpaths if the volume has none
    self_tiles: bool             # whether the basemap is served from this origin
    photon_url: str              # the Photon instance search asks; "" turns search off
    poll_veh: float
    epoch: float
    dev: bool
    argon2: dict = field(default_factory=lambda: dict(
        time_cost=3, memory_cost=64 * 1024, parallelism=2))

    @property
    def cfg(self):
        return config.BY_NAME[self.variant]


def load():
    variant = _env("VARIANT", "slow-day")
    if variant not in config.BY_NAME:
        raise RuntimeError(f"{ENV}VARIANT={variant!r} is not one of "
                           f"{', '.join(config.BY_NAME)}")
    registration = _env("REGISTRATION", "code")
    if registration not in ("open", "code", "closed"):
        raise RuntimeError(f"{ENV}REGISTRATION must be open, code or closed")
    dev = _flag("DEV", False)
    origins = tuple(o.strip() for o in _env("ORIGINS", "").split(",") if o.strip())
    if not origins and not dev:
        raise RuntimeError(f"{ENV}ORIGINS must list the exact origins the web "
                           f"app is served from, e.g. https://lviv.example.org")
    return Settings(
        database_url=_env("DATABASE_URL"),
        variant=variant,
        secure_cookies=_flag("SECURE_COOKIES", not dev),
        origins=origins,
        web_base=_env("WEB_BASE", origins[0] if origins else "").rstrip("/"),
        registration=registration,
        session_idle=float(_env("SESSION_IDLE_S", 3600 * 12)),
        session_max=float(_env("SESSION_MAX_S", 86400 * 7)),
        remember_days=float(_env("REMEMBER_DAYS", 60)),
        trust_proxy=_flag("TRUST_PROXY", False),
        build_planner=_flag("BUILD_PLANNER", True),
        self_tiles=_flag("SELF_TILES", False),
        photon_url=_env("PHOTON_URL", "https://photon.komoot.io").rstrip("/"),
        poll_veh=float(_env("POLL_VEH_S", 5.0)),
        epoch=float(_env("EPOCH_S", 60.0)),
        dev=dev,
    )
