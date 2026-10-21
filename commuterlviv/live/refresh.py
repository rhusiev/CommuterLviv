"""The city kept current while it is served.

Every night at `CHECK_AT` the static feed is fetched again, every `WALK_EVERY`
the footpaths are, and every `geocode.INDEX_EVERY` the place index is. Whatever
changed is rebuilt beside the running service, in threads, and swapped in at
once: nobody waits on a rebuild, and a failed one leaves the old city serving,
to be tried again the next night. Then the recording is searched for listed
stops the vehicles drive past, for an operator to read.
"""
import asyncio
import dataclasses
import datetime
import json
import time

from .. import gtfs, localtime, network, skipped, snapshot, walk as footpaths
from ..logs import brief
from . import geocode, geometry, journeys, state, traffic

CHECK_AT = datetime.time(3, 30)     # local: after the last tram, before the first
WALK_EVERY = 30 * localtime.DAY_S  # s between footpath refetches
SHRINK = 0.5    # of the routes a new feed may keep before it is taken as broken
LOG_SKIPPED = 20    # skipped stops logged each night; `/api/status` has them all


def served(net, live):
    """What the HTTP side hands out about a city besides its catalog, built
    once rather than per client."""
    shapes = json.dumps(geometry.describe(net, live.cat.routes)).encode()
    streets = traffic.segments(net, live.model)
    units = streets.pop("unit")
    body = json.dumps(streets).encode()
    return {"shapes_json": shapes, "shapes_tag": state.etag(shapes),
            "traffic_json": body, "traffic_tag": state.etag(body),
            "traffic_cache": traffic.Cache(live.model, units)}


def install(s, items):
    for k, v in items.items():
        setattr(s, k, v)


def _until(at):
    now = datetime.datetime.now(localtime.TZ)
    then = now.replace(hour=at.hour, minute=at.minute, second=0, microsecond=0)
    if then <= now:
        then += datetime.timedelta(days=1)
    return (then - now).total_seconds()


async def nightly(s, log):
    while True:
        await asyncio.sleep(_until(CHECK_AT))
        try:
            await check(s, log)
        except Exception as exc:
            log("refresh: keeping the city as it is -", brief(exc))
        await stops(s, log)


async def check(s, log):
    """Fetches what is due, and renews the city if any of it changed."""
    if s.settings.places_url and \
            await asyncio.to_thread(geocode.index_age) > geocode.INDEX_EVERY:
        await places(s, log)
    paths = s.settings.build_planner and footpaths.CACHE.exists() and \
        await asyncio.to_thread(footpaths.age) > WALK_EVERY
    if paths:
        log("refresh: refetching the footpaths")
        try:
            await asyncio.to_thread(footpaths.renew)
        except Exception as exc:
            log("refresh: keeping the footpaths held -", brief(exc))
            paths = False
    fetched = False
    try:
        fetched = await asyncio.to_thread(gtfs.refetch)
    except Exception as exc:
        log("refresh: keeping the feed held -", brief(exc))
    source = await asyncio.to_thread(network.source)
    if source != s.source:
        try:
            await renew(s, log)
        except Exception:
            if fetched:
                await asyncio.to_thread(gtfs.restore)
            raise
        s.source = source
    elif paths:
        await replan(s, s.svc.live, log)


async def stops(s, log):
    """The listed stops the vehicles seldom stood at this last week, kept as
    `s.skipped` for `/api/status`. Only reported: a stop comes off a route by
    a `[[remove]]` rule a person writes."""
    try:
        found = await asyncio.to_thread(skipped.check, s.svc.live.net)
    except Exception as exc:
        log("skipped stops: not checked -", brief(exc))
        return
    s.skipped = {"at": round(time.time()),
                 "stops": [dataclasses.asdict(f) for f in found]}
    log(f"skipped stops: {len(found)} listed stop(s) the vehicles seldom "
        "stood at")
    for f in found[:LOG_SKIPPED]:
        log("skipped stops:", f.line())


async def places(s, log):
    """The place index, which search reads per query and so needs no swap."""
    try:
        await asyncio.to_thread(geocode.renew_index, s.settings.places_url)
        log("refresh: the place index is renewed")
    except Exception as exc:
        log("refresh: keeping the place index held -", brief(exc))


async def renew(s, log):
    """A new feed: the network, the live model, the planner and everything
    served about them, built beside the old and swapped in together."""
    old = s.svc.live
    net = await asyncio.to_thread(network.load)
    if len(net.routes) < SHRINK * len(old.net.routes):
        raise ValueError(f"the new feed has {len(net.routes)} routes against "
                         f"{len(old.net.routes)}")
    live = await asyncio.to_thread(state.Live, net, s.settings.cfg,
                                   epoch=s.settings.epoch)
    items = await asyncio.to_thread(served, net, live)
    planner = await asyncio.to_thread(journeys.ready, net, live.cat, log,
                                      s.settings.build_planner)
    # last before the swap, so the old model has learned all it will
    since = None
    if snapshot.supported(old.model):
        async with s.svc.lock:
            held = await asyncio.to_thread(snapshot.export, old.model)
        since = await asyncio.to_thread(snapshot.restore, live.model, held)
    await asyncio.to_thread(s.svc.warm, live, since=since)
    async with s.svc.lock:
        await asyncio.to_thread(s.svc.swap, live)
        install(s, items)
        s.planner = planner
    # the new model holds the old one's rows but nothing fitted on them
    s.svc.refit.set()
    await s.hub.renew(live)
    log(f"refresh: now serving {len(live.cat.routes)} routes, "
        f"{len(live.cat.stops)} stops")


async def replan(s, live, log):
    """New footpaths under an unchanged feed: only the planner is rebuilt."""
    planner = await asyncio.to_thread(journeys.ready, live.net, live.cat, log,
                                      s.settings.build_planner)
    if planner is not None:
        s.planner = planner
        log("refresh: the planner walks the new footpaths")
