"""A websocket's reader and pusher live and die with its connection."""
import asyncio
import contextlib
import json
from types import SimpleNamespace

from commuterlviv.live import hub

WAIT_S = 5.0
CONNECTION_TASKS = 3    # the connection, its reader and its pusher


class _Socket:
    """A client that says nothing and never goes away by itself; what it is
    sent is kept in `got`."""

    def __init__(self):
        self._never = asyncio.Event()
        self.got = []

    async def send_text(self, text):
        self.got.append(json.loads(text))

    async def receive_text(self):
        await self._never.wait()

    async def close(self, code=1000):
        pass


def _live():
    cat = SimpleNamespace(routes=[], stops=[], tag="t")
    return SimpleNamespace(variant="v", epoch_s=60.0, cat=cat)


async def _nothing(client):
    pass


def test_a_connection_cancelled_mid_wait_takes_its_reader_and_pusher_with_it():
    async def run():
        h = hub.Hub(_live())
        h._send_positions = _nothing
        me = asyncio.current_task()
        serving = asyncio.create_task(h.serve(_Socket(), user_id=1))
        async with asyncio.timeout(WAIT_S):
            while len(asyncio.all_tasks() - {me}) < CONNECTION_TASKS:
                await asyncio.sleep(0)

        serving.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await serving

        assert asyncio.all_tasks() == {me}
        assert not h.clients

    asyncio.run(run())


def test_the_vehicles_going_quiet_and_back_is_told_once_each():
    async def run():
        h = hub.Hub(_live())
        h._send_positions = _nothing
        ws = _Socket()
        serving = asyncio.create_task(h.serve(ws, user_id=1))

        async def publish(quiet):
            h.quiet = quiet
            h.publish()
            # the pusher clears the wake, then sends without yielding
            async with asyncio.timeout(WAIT_S):
                while any(c.wake.is_set() for c in h.clients):
                    await asyncio.sleep(0)

        async with asyncio.timeout(WAIT_S):
            while not ws.got:
                await asyncio.sleep(0)
        for quiet in (True, True, False):
            await publish(quiet)
        serving.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await serving

        assert [m.get("quiet") for m in ws.got] == [False, True, False]
        assert [m["type"] for m in ws.got] == ["hello", "quiet", "quiet"]

    asyncio.run(run())
