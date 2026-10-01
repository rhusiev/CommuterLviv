# The collector

`python -m commuterlviv collect`, the `collector` container of the stack. It
records the live feeds into `data/feed.db` on the volume it shares with the
service, which warms its model from the last two hours of it on every start and
on every new feed.

The collector is meant to be left alone. It is a single process with one writer
thread and one thread per feed, and everything that could end a long run is
handled explicitly:

| failure | what happens |
|---|---|
| a feed starts erroring | each consecutive failure doubles the wait, up to 2 min; one success clears it |
| a write fails | retried once after 2 s, then that batch alone is dropped; the writer lives on |
| the writer stalls | the queue is capped at 500k rows and new rows are dropped and counted, so memory cannot run away |
| the write-ahead log grows | checkpointed and truncated every 5 min |
| the disk fills | collection stops cleanly at `--min-free-gb` (default 2 G) while the database can still be closed |
| the process is asked to stop | SIGTERM stops the pollers, drains the queue and closes the file |
| the machine reboots, or the process dies | Docker restarts it (`restart: unless-stopped`); the database is append-only, so a restart just resumes |
| the static feed changes overnight | it only takes the stop list for the arrivals board from it; the service follows a new feed on its own (see [keeping the city current](service.md#keeping-the-city-current)) |

Every 5 minutes it prints one line - rows and polls per feed, error counts, queue
depth, rows dropped, database size, disk free. That line is the whole health
check.

## Disk

This is the only resource that actually binds. Measured on live feeds:

| feed | rows/day | share |
|---|---|---|
| `pred` (trip_updates) | ~3.4 M | 58% |
| `veh` (vehicle_position) | ~2.0 M | 35% |
| `lad` (arrivals board) | ~0.4 M | 7% |

About **0.7 GB/day**, so 5 GB for a week and 22 GB for a month. Budget double.

`pred` used to be three times that. The feed republishes every stop of every
trip on every poll, and most of what changes between polls is a second or two of
jitter on a number scored against a 60 s grid, so `--pred-deadband` (default 5 s)
stores a prediction only once it has moved further than that. It cuts the feed to
a third and costs nothing measurable, since 5 s is a seventh of the API's own
median error at the shortest horizon. Set it to `0` to record the feed verbatim.

`--keep-days N` drops rows older than N days once an hour and hands the space
back to the filesystem. It only shrinks the file on a database created by this
version, which asks SQLite for incremental auto-vacuum up front; on an older file
the pages are freed inside the file but never returned.

`veh` is indexed on `veh_ts` too, which is what lets the service find the last
two hours without reading the whole file - without it, warming on a 35 GB
recording took 25 s. A collector of this version adds the index to an older
recording on its first write, which takes minutes on one that size; the rows
polled meanwhile wait in the queue.

## Two collectors at once

Don't. Both would poll the same feeds twice as often for no extra information.
Once a server is recording, stop any other collector.

The databases can be merged afterwards - rows are append-only and `veh` is keyed
on `(veh_id, veh_ts)`, so overlapping periods deduplicate themselves:

```sh
python3 - <<'EOF'
import sqlite3
db = sqlite3.connect("data/feed.db")
db.execute("ATTACH 'other.db' AS o")
for t in ("poll", "veh", "pred", "lad"):
    db.execute(f"INSERT OR IGNORE INTO {t} SELECT * FROM o.{t}")
db.commit()
EOF
```

`pred` and `lad` have no primary key, so merging the same file twice duplicates
them; merge each source once.

Take the copy while the collector is running with SQLite's own backup, not with
`docker cp`. The database is in WAL mode, so the newest rows are in
`feed.db-wal` and a plain copy of `feed.db` is both missing them and possibly
torn. The image's own python does it:

```sh
docker compose exec -T service python -c "import sqlite3; \
  sqlite3.connect('data/feed.db').backup(sqlite3.connect('data/snapshot.db'))"
docker compose cp service:/app/data/snapshot.db ./feed-snapshot.db
docker compose exec -T service rm /app/data/snapshot.db
```

The snapshot is as large as the recording, so delete it once it is copied - the
collector stops at 3 GB free.
