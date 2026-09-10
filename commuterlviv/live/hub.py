"""One websocket per client, and what gets pushed down it.

Every client is looking at the same city, so nothing here recomputes anything
per client: the engine publishes one immutable snapshot and each connection
takes the slice its filter asks for.

There is no send queue. A client that has fallen behind does not accumulate
frames it no longer wants - it wakes up, looks at the current state, and sends
the difference between that and what it last managed to deliver. A client whose
train went into a tunnel therefore costs one frame when it comes back rather
than two hundred stale ones, and the server's memory does not depend on the
slowest client connected to it.
"""
import asyncio
import json
import time

import numpy as np

from . import wire

MAX_STOPS = 64          # stops one client may have open at once
IDLE_PING = 30.0        # s of quiet before the server says something
MAX_MSG = 4 * 1024      # a client message is a filter, never a payload

# What a client may ask for. A person changing routes as fast as a person can
# spends about one a second and the app coalesces nothing, so this is generous
# by an order of magnitude; what it is here for is the client that loops.
MSG_RATE = 5.0          # messages a second, sustained
MSG_BURST = 60.0
MSG_ABUSE = 500         # messages refused before the socket is closed

# Sockets one account may hold open. A phone, a laptop and a tab each is four,
# and the handshake rate limit only bounds how fast they are opened, not how
# many are left open
MAX_PER_USER = 8


def due(arrivals, stops):
    """What is coming to these stops, as the wire says it. Shared with
    `/api/arrivals`, so the socket and the request cannot word it differently."""
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
    """The published state, and everyone watching it.

    Waking clients is a counter and one event each rather than a per-client
    queue. The counter is what makes it race-free: a client that was busy
    sending when the engine published compares sequence numbers, sees it is
    behind, and goes straight round again instead of waiting for an event that
    has already been and gone.

    The events are per client and not one shared event because a client's own
    message must not cost anything to the rest: changing a route filter wakes
    the connection that asked and no other, where one shared event would put
    every open map in the city through a diff.
    """

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
            # Whichever half stops first ends the connection: a pusher that
            # died on a bug would otherwise leave a socket that reads fine and
            # never updates again
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
        """Client requests. Only three, and each is bounded by the catalog: a
        filter cannot name a route that does not exist and a watch list has a
        length limit, so no message a client sends makes the server allocate."""
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
            # Cleared before the state is read, so a publish that lands in
            # between leaves the event set and is not missed
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
