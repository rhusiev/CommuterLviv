"""The loops: poll the feed, step the model, wake the clients.

Everything touching the tracker or the model runs in one worker thread behind a
lock, to keep ~200 ms of numpy per epoch off the event loop.

This does not write `feed.db` - the collector owns it - so the two poll the same
endpoint independently.
"""
import asyncio
import sqlite3
import time

from .. import collect, layover, replay, snapshot
from .state import Live

WARM_HOURS = 2.0         # of recorded history replayed at most, if it is fresh
WARM_MAX_AGE = 900.0     # s: older than this and the recording is not "now"
SAVE_EVERY = 600.0       # s between snapshots of the model
FIT_EVERY = 6 * 3600.0   # s between refits of the terminus departure model


class Service:
    def __init__(self, settings, net, catalog=None, log=print, persist=True):
        self.set = settings
        self.log = log
        self.live = Live(net, settings.cfg, catalog, epoch=settings.epoch)
        self.persist = persist and snapshot.supported(self.live.model)
        self.lock = asyncio.Lock()
        self.hub = None          # set by the app, which owns the connections
        self.errors = 0
        self.polls = 0
        self._seen = {}

    async def start(self, hub):
        self.hub = hub
        since = None
        if self.persist:
            since = await asyncio.to_thread(snapshot.load, self.live.model)
            self.log("no model snapshot; learning from scratch" if since is None
                     else f"model snapshot from {time.time() - since:.0f}s ago")
        await asyncio.to_thread(self.warm, since=since)
        tasks = [self.poll_loop(), self.epoch_loop(), self.fit_loop()]
        if self.persist:
            tasks.append(self.save_loop())
        return [asyncio.create_task(t) for t in tasks]

    def warm(self, live=None, db=None, since=None):
        """Catch the model up on the recording made since `since`, the time its
        state was taken, by at most `WARM_HOURS`; a cold model knows only the
        timetable."""
        live, db = live or self.live, db or replay.DB
        try:
            con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
            last = con.execute("SELECT max(veh_ts) FROM veh").fetchone()[0]
            con.close()
        except sqlite3.Error as exc:
            self.log("no recording to warm from:", repr(exc)[:120])
            return False
        if not last or time.time() - last > WARM_MAX_AGE:
            self.log("recording is stale; starting the model cold")
            return False
        t0 = time.time()
        t_from = max(last - WARM_HOURS * 3600, since or 0.0)
        try:
            replay.run(live.net, t_from=t_from, t_to=last,
                       db=db, model=live.model, epoch=self.set.epoch)
        except replay.NoData as exc:
            self.log("nothing to warm from:", str(exc)[:120])
            return False
        self.log(f"warmed the model on {(last - t_from) / 60:.0f} min of "
                 f"recording in {time.time() - t0:.1f}s")
        return True

    async def save_loop(self):
        while True:
            await asyncio.sleep(SAVE_EVERY)
            try:
                await self.save()
            except Exception as exc:
                self.log("model snapshot failed", repr(exc)[:200])

    async def save(self):
        async with self.lock:
            data = await asyncio.to_thread(snapshot.export, self.live.model)
        await asyncio.to_thread(snapshot.save, data)

    async def fit_loop(self):
        """Refit the terminus departure model (`layover.fit`) on start and
        every `FIT_EVERY`, outside the lock: a fit takes seconds of CPU."""
        while True:
            try:
                async with self.lock:
                    lay = self.live.model.layovers
                    rows = lay.training()
                fitted = await asyncio.to_thread(layover.fit, rows)
                if fitted is not None:
                    async with self.lock:
                        lay.model = fitted
                    self.log(f"terminus model fitted on {len(rows)} minutes of stands")
            except Exception as exc:
                self.log("terminus model fit failed", repr(exc)[:200])
            await asyncio.sleep(FIT_EVERY)

    def swap(self, live):
        """Onto a new city, primed with a poll and an epoch so it is not
        published empty. Runs in a worker thread, holding the lock."""
        self.live = live
        self._seen.clear()
        try:
            self.poll_once()
            live.epoch()
        except Exception as exc:
            self.log("first poll of the new city failed", repr(exc)[:200])

    async def poll_loop(self):
        fails = 0
        while True:
            t0 = time.time()
            try:
                async with self.lock:
                    n = await asyncio.to_thread(self.poll_once)
                self.polls += 1
                fails = 0
                self.hub.publish()
                if self.polls % 60 == 0:
                    self.log(f"poll {self.polls}: {n} new fixes, "
                             f"{len(self.live.positions.veh)} vehicles, "
                             f"{len(self.hub.clients)} clients")
            except Exception as exc:
                self.errors += 1
                fails += 1
                if fails in (1, 5) or fails % 50 == 0:
                    self.log(f"poll error x{fails}", repr(exc)[:200])
            wait = min(self.set.poll_veh * 2 ** min(fails, 8),
                       collect.BACKOFF_MAX) if fails else self.set.poll_veh
            await asyncio.sleep(max(0.5, wait - (time.time() - t0)))

    def poll_once(self):
        """One fetch, folded in. Runs in a worker thread."""
        msg = collect.rt("vehicle_position")
        n = 0
        for e in msg.entity:
            v = e.vehicle
            key = v.vehicle.id
            if not key or self._seen.get(key) == v.timestamp:
                continue
            self._seen[key] = v.timestamp
            p = v.position
            if self.live.fix(key, v.timestamp, p.latitude, p.longitude,
                             p.speed, p.odometer, v.trip.trip_id or None):
                n += 1
        if len(self._seen) > 100_000:
            self._seen.clear()
        self.live.poll_done()
        return n

    async def epoch_loop(self):
        """On the absolute epoch grid, so live epochs land on the same
        boundaries the offline replay uses."""
        while True:
            step = self.set.epoch
            await asyncio.sleep(step - time.time() % step)
            t = time.time()
            try:
                async with self.lock:
                    await asyncio.to_thread(self.live.epoch)
                self.hub.publish(epoch=True)
            except Exception as exc:
                self.errors += 1
                self.log("epoch error", repr(exc)[:200])
            took = time.time() - t
            if took > step / 2:
                self.log(f"epoch took {took:.1f}s of a {step:.0f}s budget")

    def health(self):
        return {**self.live.health(), "polls": self.polls, "errors": self.errors}
