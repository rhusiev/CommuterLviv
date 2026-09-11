"""The connection pool and the migration runner.

Migrations are numbered files in `migrations/`, applied in order, one
transaction each, with the number recorded. There is no down direction.
"""
import os

import asyncpg

HERE = os.path.join(os.path.dirname(__file__), "migrations")

BOOTSTRAP = """
CREATE TABLE IF NOT EXISTS schema_migrations(
  version integer PRIMARY KEY,
  name text NOT NULL,
  applied_at timestamptz NOT NULL DEFAULT now());
"""


async def connect(url, min_size=1, max_size=8):
    return await asyncpg.create_pool(url, min_size=min_size, max_size=max_size,
                                     command_timeout=10.0)


def files():
    return sorted((int(f.split("_")[0]), f) for f in os.listdir(HERE)
                  if f.endswith(".sql"))


async def migrate(pool, log=print):
    async with pool.acquire() as con:
        await con.execute(BOOTSTRAP)
        done = {r["version"] for r in
                await con.fetch("SELECT version FROM schema_migrations")}
        for version, name in files():
            if version in done:
                continue
            with open(os.path.join(HERE, name)) as f:
                sql = f.read()
            async with con.transaction():
                await con.execute(sql)
                await con.execute("INSERT INTO schema_migrations(version, name) "
                                  "VALUES($1, $2)", version, name)
            log(f"migrated {name}")
