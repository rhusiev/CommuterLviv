"""The loops: poll the feed, step the model, wake the clients.

Everything touching the tracker or the model runs in one worker thread behind a
lock, to keep ~200 ms of numpy per epoch off the event loop.

This does not write `feed.db` - the collector owns it - so the two poll the same
endpoint independently.
"""
import asyncio
import sqlite3
import time

from .. import collect, replay
from .state import Live

WARM_HOURS = 2.0         # of recorded history replayed at boot, if it is fresh
WARM_MAX_AGE = 900.0     # s: older than this and the recording is not "now"


class Service:
    def __init__(self, settings, net, catalog=None, log=print):
        self.set = settings
        self.log = log
        self.live = Live(net, settings.cfg, catalog, epoch=settings.epoch)
        self.lock = asyncio.Lock()
        self.hub = None          # set by the app, which owns the connections
        self.errors = 0
        self.polls = 0
        self._seen = {}

    async def start(self, hub):
        self.hub = hub
        await asyncio.to_thread(self.warm)
        return [asyncio.create_task(self.poll_loop()),
                asyncio.create_task(self.epoch_loop())]

    def warm(self, db=None):
        """Prime the model by replaying the recording, when there is a fresh
        one; a cold model knows only the timetable."""
        db = db or replay.DB
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
        try:
            replay.run(self.live.net, t_from=last - WARM_HOURS * 3600, t_to=last,
                       db=db, model=self.live.model, epoch=self.set.epoch)
        except replay.NoData as exc:
            self.log("nothing to warm from:", str(exc)[:120])
            return False
        self.log(f"warmed the model on {WARM_HOURS:.0f}h of recording "
                 f"in {time.time() - t0:.1f}s")
        return True

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
