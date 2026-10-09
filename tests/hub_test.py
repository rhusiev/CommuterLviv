"""A websocket's reader and pusher live and die with its connection."""
import asyncio
import contextlib
from types import SimpleNamespace

from commuterlviv.live import hub

WAIT_S = 5.0
CONNECTION_TASKS = 3    # the connection, its reader and its pusher


class _Socket:
    """A client that says nothing and never goes away by itself."""

    def __init__(self):
        self._never = asyncio.Event()

    async def send_text(self, text):
        pass

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
