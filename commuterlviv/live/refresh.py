"""The city kept current while it is served.

Every night at `CHECK_AT` the static feed is fetched again, and every
`WALK_EVERY` the footpaths are. Whatever changed is rebuilt beside the running
service, in threads, and swapped in at once: nobody waits on a rebuild, and a
failed one leaves the old city serving, to be tried again the next night.
"""
import asyncio
import datetime
import json

from .. import gtfs, network, plan, snapshot, walk as footpaths
from . import geometry, journeys, state, traffic

CHECK_AT = datetime.time(3, 30)     # local: after the last tram, before the first
WALK_EVERY = 30 * 86400.0           # s between footpath refetches
SHRINK = 0.5    # of the routes a new feed may keep before it is taken as broken


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
    now = datetime.datetime.now(plan.TZ)
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
            log("refresh: keeping the city as it is -", repr(exc)[:200])


async def check(s, log):
    """Fetches what is due, and renews the city if any of it changed."""
    paths = s.settings.build_planner and footpaths.CACHE.exists() and \
        await asyncio.to_thread(footpaths.age) > WALK_EVERY
    if paths:
        log("refresh: refetching the footpaths")
        try:
            await asyncio.to_thread(footpaths.renew)
        except Exception as exc:
            log("refresh: keeping the footpaths held -", repr(exc)[:200])
            paths = False
    fetched = False
    try:
        fetched = await asyncio.to_thread(gtfs.refetch)
    except Exception as exc:
        log("refresh: keeping the feed held -", repr(exc)[:200])
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
