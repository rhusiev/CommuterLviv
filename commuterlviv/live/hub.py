"""One websocket per client, and what gets pushed down it.

The engine publishes one immutable snapshot and each connection takes the slice
its filter asks for. There is no send queue: a client that fell behind wakes up,
reads the current state, and sends the difference from what it last delivered, so
server memory does not depend on the slowest client.
"""
import asyncio
import json
import time

import numpy as np

from . import wire

MAX_STOPS = 64          # stops one client may have open at once
IDLE_PING = 30.0        # s of quiet before the server says something
MAX_MSG = 4 * 1024      # a client message is a filter, never a payload

MSG_RATE = 5.0          # messages a second, sustained
MSG_BURST = 60.0
MSG_ABUSE = 500         # messages refused before the socket is closed

MAX_PER_USER = 8        # sockets one account may hold open at once


def due(arrivals, stops):
    """What is coming to these stops; shared with `/api/arrivals`."""
    return {"t": arrivals.t, "stops": {
        str(i): [{"route": int(r["route"]), "veh": int(r["veh"]),
                  "t": int(r["t"])} for r in arrivals.at(i)] for i in stops}}


class Client:
    __slots__ = ("ws", "user_id", "routes", "stops", "last", "frames", "bytes",
                 "wake", "tokens", "at", "refused")

    def __init__(self, ws, user_id, nroutes):
        self.ws = ws
        self.user_id = user_id
        self.routes = np.zeros(nroutes, bool)
        self.stops = []
        self.last = None        # what this client is known to hold; None asks
        self.frames = self.bytes = 0        # for a snapshot
        self.wake = asyncio.Event()
        self.tokens, self.at = MSG_BURST, time.monotonic()
        self.refused = 0

    def spend(self):
        """Whether this client may send one more message just now."""
        now = time.monotonic()
        self.tokens = min(MSG_BURST, self.tokens + (now - self.at) * MSG_RATE)
        self.at = now
        if self.tokens < 1.0:
            self.refused += 1
            return False
        self.tokens -= 1.0
        return True


class Hub:
    """The published state, and everyone watching it. Waking is a sequence
    counter plus one event per client: the counter keeps it race-free, since a
    client busy at publish time sees it is behind rather than waiting on an
    event already set and cleared."""

    def __init__(self, live):
        self.live = live
        self.clients = set()
        self.seq = 0
        self.epoch_seq = 0

    def publish(self, epoch=False):
        self.seq += 1
        if epoch:
            self.epoch_seq += 1
        for client in self.clients:
            client.wake.set()

    async def serve(self, ws, user_id):
        """One connection, until it goes away."""
        if sum(c.user_id == user_id for c in self.clients) >= MAX_PER_USER:
            await ws.close(code=1013)
            return
        client = Client(ws, user_id, len(self.live.cat.routes))
        self.clients.add(client)
        try:
            await ws.send_text(json.dumps({
                "type": "hello", "variant": self.live.variant,
                "epoch": self.live.epoch_s,
                "routes": len(self.live.cat.routes),
                "stops": len(self.live.cat.stops)}))
            # whichever half stops first ends the connection, so a dead pusher
            # cannot leave a socket that reads fine and never updates
            tasks = [asyncio.create_task(self._read(client)),
                     asyncio.create_task(self._push(client))]
            done, pending = await asyncio.wait(
                tasks, return_when=asyncio.FIRST_COMPLETED)
            for t in pending:
                t.cancel()
            await asyncio.gather(*pending, return_exceptions=True)
            for t in done:
                t.result()
        finally:
            self.clients.discard(client)

    async def _read(self, client):
        """Client requests; each is bounded by the catalog, so no client message
        makes the server allocate."""
        while True:
            raw = await client.ws.receive_text()
            if not client.spend():
                if client.refused > MSG_ABUSE:
                    await client.ws.close(code=1008)
                    return
                continue
            if len(raw) > MAX_MSG:
                continue
            try:
                msg = json.loads(raw)
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue
            if not isinstance(msg, dict):
                continue
            kind = msg.get("type")
            if kind == "routes":
                client.routes = self._mask(msg.get("routes"))
                client.last = None
                client.wake.set()
            elif kind == "stops":
                client.stops = self._watch(msg.get("stops"))
                await self._send_arrivals(client)
            elif kind == "ping":
                await client.ws.send_text(json.dumps({"type": "pong",
                                                      "t": time.time()}))

    def _mask(self, want):
        mask = np.zeros(len(self.live.cat.routes), bool)
        for i in (want or [])[:len(mask)]:
            if isinstance(i, int) and 0 <= i < len(mask):
                mask[i] = True
        return mask

    def _watch(self, want):
        n = len(self.live.cat.stops)
        return [i for i in (want or [])[:MAX_STOPS]
                if isinstance(i, int) and 0 <= i < n]

    async def _push(self, client):
        seen, seen_epoch = -1, self.epoch_seq
        while True:
            if seen == self.seq and not client.wake.is_set():
                try:
                    await asyncio.wait_for(client.wake.wait(), IDLE_PING)
                except TimeoutError:
                    await client.ws.send_text(json.dumps({"type": "pong",
                                                          "t": time.time()}))
                    continue
            # cleared before reading the state, so a publish landing in between
            # leaves the event set and is not missed
            client.wake.clear()
            seen = self.seq
            await self._send_positions(client)
            if self.epoch_seq != seen_epoch:
                seen_epoch = self.epoch_seq
                if client.stops:
                    await self._send_arrivals(client)

    async def _send_positions(self, client):
        pos = self.live.positions
        rows = wire.inbox(pos.by_route(client.routes))
        if client.last is None:
            frame = wire.encode(rows, pos.t, wire.SNAPSHOT)
        else:
            delta, gone = wire.changed(client.last, rows)
            if not len(delta) and not len(gone):
                return
            frame = wire.encode(delta, pos.t, wire.DELTA, gone)
        await client.ws.send_bytes(frame)
        client.last = rows
        client.frames += 1
        client.bytes += len(frame)

    async def _send_arrivals(self, client):
        arr = self.live.arrivals
        await client.ws.send_text(json.dumps(
            {"type": "arrivals", **due(arr, client.stops)}))

    def stats(self):
        return {"clients": len(self.clients),
                "frames": sum(c.frames for c in self.clients),
                "bytes": sum(c.bytes for c in self.clients),
                "refused": sum(c.refused for c in self.clients)}
