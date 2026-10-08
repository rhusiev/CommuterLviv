"""A throwaway Postgres for the tests that need the service's database.

`COMMUTERLVIV_TEST_DATABASE_URL` names one to use as it is - it must be
disposable, since the tests write to it. Otherwise a container is started with
podman or docker and removed afterwards; with neither, the tests are skipped.
"""
import asyncio
import contextlib
import os
import shutil
import subprocess
import time
import uuid

import asyncpg
import pytest

ENV = "COMMUTERLVIV_TEST_DATABASE_URL"
IMAGE = "docker.io/library/postgres:16-alpine"
READY_S = 60.0
PASSWORD = "test"


async def _ready(url):
    con = await asyncpg.connect(url, timeout=2.0)
    await con.close()


def _wait(url, runner):
    deadline = time.monotonic() + READY_S
    while True:
        try:
            asyncio.run(_ready(url))
            return
        # the image restarts its server once initialised, dropping connections
        except (OSError, asyncpg.PostgresError, asyncpg.InterfaceError, TimeoutError):
            if time.monotonic() > deadline:
                raise RuntimeError(
                    f"{runner}'s Postgres was not ready in {READY_S:.0f} s")
            time.sleep(0.5)


def _port(runner, name):
    """The host port the runner picked for the container's Postgres."""
    out = subprocess.run([runner, "port", name, "5432/tcp"], check=True,
                         capture_output=True, text=True).stdout
    return int(out.split()[0].rsplit(":", 1)[1])


@contextlib.contextmanager
def server():
    """The URL of a Postgres to write to, for as long as the block runs."""
    if url := os.environ.get(ENV):
        yield url
        return
    runner = shutil.which("podman") or shutil.which("docker")
    if runner is None:
        pytest.skip(f"needs podman or docker, or {ENV}")
    name = f"commuterlviv-test-{uuid.uuid4().hex[:8]}"
    subprocess.run([runner, "run", "-d", "--rm", "--name", name,
                    "-e", f"POSTGRES_PASSWORD={PASSWORD}",
                    "-p", "127.0.0.1::5432", IMAGE],
                   check=True, capture_output=True)
    try:
        port = _port(runner, name)
        url = f"postgresql://postgres:{PASSWORD}@127.0.0.1:{port}/postgres"
        _wait(url, runner)
        yield url
    finally:
        subprocess.run([runner, "rm", "-f", name], capture_output=True, check=False)
