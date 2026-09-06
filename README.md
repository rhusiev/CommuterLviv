# lvivpred

Arrival-time prediction for Lviv public transport, and a measurement of how it
compares with the city's own.

```
python3 -m lvivpred collect      # record the live feeds into data/feed.db
python3 -m lvivpred evaluate     # replay what was recorded and score everything
python3 -m lvivpred experiment   # score every approach on the same recording
python3 -m lvivpred check        # model, tracking or truth: which one is wrong
python3 -m lvivpred diag         # what methodology is the official API using
```

Needs `numpy`, `requests` and `protobuf`. Everything it downloads or learns
lives in `data/` and is rebuilt on demand.

## What this answers

**How does a GPS fix from the city's feed become a predicted arrival time at a
stop, and how do we know the prediction is any good?**

The trace below follows one position fix from the moment it arrives to the
moment its prediction is scored. Every step names the file it happens in.

### 1. A fix arrives, roughly every 10 seconds per vehicle

`collect.py` polls three feeds and writes rows into an SQLite file,
`data/feed.db`:

- `https://track.ua-gis.com/gtfs/lviv/vehicle_position` every 5 s - a protobuf
  with, for each vehicle, its id, timestamp, latitude, longitude, speed,
  odometer reading in km, and the trip it is running
- `.../trip_updates` every 15 s - the city's own predicted arrival time for
  every upcoming stop of every trip. This is the thing being competed with
- `https://api.lad.lviv.ua/stops/<code>` every 60 s for 40 stops - the public
  arrivals board, a second and slightly different official prediction

Each row is stamped with both the vehicle's own timestamp and the moment we
polled. The replay later filters on the difference: a fix more than 300 s stale,
or 60 s in the future, is thrown away.

### 2. The fix is placed on a line, not a map

`network.py` builds the geometry once from the static GTFS feed
(`static.zip`, refreshed daily) and caches it in `data/network.pkl`.

Latitude and longitude are converted to metres by a flat local projection about
49.84 N, 24.03 E - over a city this size the error is negligible and it makes
every later operation arithmetic instead of trigonometry.

Every trip follows a *shape*, a polyline. A vehicle's position is then reduced
to one number: **distance along that shape, in metres**. Two dimensions become
one, and a stop becomes a scalar - a number of metres from the start of the
line. That single decision is what makes the rest cheap.

Stops are placed on the shape by a Viterbi pass over their candidate positions:
each stop can plausibly sit at several points on a line that doubles back, so
the assignment chosen is the one with the least total lateral error among all
strictly increasing assignments. Trips sharing a shape *and* a stop list have
identical geometry, so this is solved once per pattern - 185 patterns cover
15903 trips over 182 shapes.

Each shape is also cut into 100 m **cells**, and each cell is tagged with a
**corridor** key: which 120 m ground square it sits in, and which of 8 compass
octants it points along. Two routes driving the same street the same way land
in the same corridor even though they are different shapes. That is how
evidence gets pooled across routes.

### 3. The fix is folded into a filter, not used directly

`track.py` keeps one `Track` per vehicle: a 2-state Kalman filter on
(distance along shape, speed).

The prediction step does *not* difference two map-matched positions. It uses the
vehicle's own odometer increment, because the odometer is an integrated path
length good to about 2 m, while map-matching error is correlated between
neighbouring fixes and would bias the increment systematically. GPS still
enters, but only as a correction of absolute position, with 12 m assumed
along-track snap error and 1.5 m/s assumed speed error. A snap more than 60 m
off the line is refused; 300 s without a fix, or 150 m of backwards motion,
resets the track (the latter is a loop restart, not noise).

Measured against interpolated truth, the filtered position is off by a median of
+6 m, with p5 and p95 at -159 m and +169 m.

### 4. The interval since the last fix is charged to the road

Also `track.py`, in `_spread`. The time between two fixes is split in two,
because the road spends it in two ways that behave nothing alike:

- **pace** - seconds per metre while rolling. Scales with distance. Stored as
  pace rather than speed because travel time is *linear* in pace: paces can be
  averaged and added, speeds cannot.
- **hold** - seconds standing still per crossing of a cell. Scales with
  nothing. A bus stop, a red light, a queue at a junction. Charged whole to the
  cell it happened in.

A vehicle counts as standing when it moved under 3 m and reports under
0.7 m/s. Rolling time is divided between the cells crossed in proportion to the
distance covered in each.

A single speed cannot express standing still - as distance goes to zero the
implied speed goes to zero, and any clip on it silently discards the wait - so
pace and hold stay apart until an arrival time is actually wanted.

Two rules keep the evidence honest. A cell the vehicle was already half way
through when the track started is never reported, because its totals are
missing whatever happened before. And a crossing is reported *while it is still
in progress*, not only when it ends: waiting for the end reports every fast
crossing sooner than every slow one, so the model would hear about a jam only
after the jam had cleared. In-progress reports carry the fraction of the
crossing's weight that has elapsed; the rest arrives when it finishes.

### 5. The road updates the model, once a minute

`model.py`. Time to cross a cell is `length x pace + hold`, and both terms are
learned in three nested layers, each backing off to the next when it has too
little data:

| layer | what it covers | how much data |
|---|---|---|
| cell | one 100 m slice of one shape | sparsest, most specific |
| corridor | a 120 m square plus heading, pooled across routes | middling |
| global | one number for the network | always available |

Each layer keeps two exponentially weighted means: a **fast** one with a 480 s
half-life, which is what traffic is doing right now, and a **slow** one with a
5400 s half-life, which is the baseline for this stretch of road. Both are
weighted by evidence, so the fast one wins wherever it has support and the slow
one carries the cell where it does not. Shrinkage between layers is by effective
count with K = 4: a cell needs about four observations before it outweighs its
corridor.

Pace is **not** learned directly. What is learned is a *multiplier* on the pace
the timetable implies for that cell at that hour of day. The timetable is not
just a fallback - it already knows two useful things: that the old town is
slower than the ring road, and that five in the afternoon is slower than five in
the morning. 155 of the 185 patterns have non-constant scheduled timings, and
total run time varies across the day by 1.11x at the median pattern and 1.93x at
the worst. So `_schedule_prior` builds a `24 hours x 26712 cells` table of
timetabled pace, interpolated between hour slots so a prediction made at 08:55
for 09:10 does not jump when the clock ticks over, and the layers only have to
explain the *ratio* the timetable got wrong. That ratio is a far smaller and far
more poolable quantity than pace itself. In practice the learned global ratio
settles near 1.01x - the timetable's shape is right, and the model corrects it
locally.

Hold has no such prior and is learned in seconds, starting at zero. It settles
around 1.9 s per cell, which drops the effective speed from 17.4 km/h rolling to
16.0 km/h door to door.

Updates are batched to a 60 s epoch: repeated cells within the batch are
collapsed into one weighted mean first, since fancy-index assignment would
otherwise keep only the last of them.

### 6. An ETA is a subtraction

`replay.py`, `_flush`. Once per epoch, after the model has been updated and
before anything is emitted, `model.refresh` recomputes per-cell time for all
26712 cells and takes one cumulative sum. An arrival time for any stop is then
the difference of two entries in that array plus a linear term inside the
partial cells at either end - O(1) per stop, whatever the distance.

For each tracked vehicle the current position is dead-reckoned forward by at
most 60 s from its last fix, and every remaining stop within a 45 minute horizon
gets a predicted arrival. That horizon matches the API's own.

The whole pass is strictly causal: one forward sweep in timestamp order, model
read only after it has been written, so nothing downstream can leak backwards
into a prediction. A full replay of the current database takes about 17 s.

### 7. Truth is measured, not assumed

`track.py` records the moment each stop was actually passed, by interpolating
between the two fixes either side of it. `truth.py` then keeps only the
**unambiguous** crossings: an event is dropped if the same (trip, stop) or the
same (vehicle, stop) occurs more than once in the window, since then no
predictor's naming can be matched to it without guessing.

The yardstick's own precision is checked and reported: the interval a crossing
was interpolated across is 16 s at the median, 52 s at p90, 299 s at worst. That
is well below the differences being measured, so the comparison is measuring
predictors and not the feed.

### 8. Four predictors are scored on identical support

`predictors.py` puts all four into one shape - (event, epoch, horizon, error):

- **ours** - the model above
- **api** - the city's `trip_updates`, replayed as it was published
- **lad** - the public arrivals board at `api.lad.lviv.ua`
- **schedule** - the timetable, unmodified, as a floor

`score.py` then reports twice. First each predictor on everything it answered.
Then - this is the honest number - all four restricted to the crossings *and*
instants that every one of them answered, so nobody is credited for being
selective. Coverage is reported as a metric in its own right, not hidden.
Confidence intervals are bootstrapped resampling whole trips, not individual
predictions, since predictions within a trip are heavily correlated.

`state.py` saves the learned model to `data/model.npz` between runs, keyed by a
hash of the shape geometry so a rebuilt feed refuses a stale snapshot. Every
weight carries the time it was earned and decays from that stamp, so an old
snapshot fades back to the timetable prior on its own. This is what lets the
replay start warm: coverage rises from 90.5% to 98.2% of truth, and 0-1 minute
MAE from 22 s to 17 s.

## What it comes out at

Warm start, ~95 minutes of recorded feed, all four predictors on identical
support. Error in seconds, `<60s` is the fraction of predictions inside a
minute.

| horizon | predictor | MAE | median | <60s | <120s |
|---|---|---|---|---|---|
| 0-1 min | **ours** | **24** | **14** | **92.9%** | **97.2%** |
| | api | 118 | 35 | 72.4% | 83.6% |
| | lad | 81 | 37 | 69.9% | 86.3% |
| | schedule | 720 | 436 | 11.2% | 21.2% |
| 2-5 min | **ours** | **65** | **42** | **63.7%** | **85.8%** |
| | api | 145 | 72 | 42.8% | 69.4% |
| | lad | 101 | 50 | 56.6% | 79.5% |
| 5-10 min | **ours** | **108** | **72** | **44.0%** | **68.3%** |
| | api | 186 | 115 | 28.0% | 52.0% |
| | lad | 133 | 79 | 40.9% | 66.2% |
| 10-20 min | **ours** | **152** | **102** | **33.7%** | **56.0%** |
| | api | 215 | 132 | 24.4% | 46.0% |
| | lad | 244 | 125 | 27.9% | 48.7% |

At a one minute horizon our median error is 14 s against the API's 35 s, and we
land inside a minute 93% of the time against its 72%.

## Why the official API is beaten so easily

`diag.py` answers this empirically, and the answer is that the API is not
measuring the road at all:

- 89.0% of consecutive-stop segments have an API travel time *identical to the
  timetable*, to the second
- predicted-minus-scheduled delay is one constant along an entire trip
- that constant drifts by a median of +0.00 s per downstream stop

So the API measures one current lateness per vehicle and adds it to a fixed
timetable. It knows the bus is four minutes late; it does not know the street it
is about to drive down is jammed. Everything above is an attempt to know that
second thing.

## The mechanisms, collapsed

Strip the code away and there are only four ideas at work:

1. **Reduce to one dimension.** Distance along a shape turns tracking,
   stop-matching, ETA and the travel-time field into arithmetic on arrays.
2. **Separate what scales from what does not.** Pace scales with distance, hold
   does not. Keeping them apart is what lets a stop, a light and a jam be
   learned as different things.
3. **Pool by geography, back off by evidence.** Cell, corridor, global; fast and
   slow. Nothing is ever without an estimate, and specificity is used exactly as
   far as the data supports it.
4. **Learn the correction, not the quantity.** The timetable already encodes
   where and when the city is slow. Learning the ratio to it means the sparse,
   fast-moving part of the problem is the only part that has to be learned from
   live data.

The one thing to take away: the official API applies a *vehicle-level* offset to
a *static* timetable, and this applies a *road-level*, *live* correction to the
same timetable. Same starting point, and the difference in where the correction
is attached is worth roughly a factor of three in median error.

## Running the collector for days

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
| the machine reboots, or the process dies | systemd restarts it; the database is append-only, so a restart just resumes |
| the static feed changes overnight | an unchanged download is not rewritten, a changed one is, and `data/network.pkl` rebuilds off its timestamp |

Every 5 minutes it prints one line - rows and polls per feed, error counts, queue
depth, rows dropped, database size, disk free. That line is the whole health
check.

### Disk

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

### On a VPS

Anything with 1 GB of RAM and 2 vCPU is ample - the process sits near 100 MB and
is almost entirely idle waiting on sockets. Disk is what you buy.

```sh
sudo adduser --system --group --home /opt/lvivpred lvivpred
sudo -u lvivpred git clone <this repo> /opt/lvivpred
cd /opt/lvivpred
sudo -u lvivpred python3 -m venv .venv
sudo -u lvivpred .venv/bin/pip install -r requirements.txt

sudo cp deploy/lvivpred.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now lvivpred
```

Then:

```sh
systemctl status lvivpred          # is it up
journalctl -u lvivpred -f          # the heartbeat line, live
journalctl -u lvivpred --since -1d | grep -c error
```

Python 3.10 or newer. Leave the machine on UTC - every timestamp stored is a Unix
epoch and nothing in the code reads the system timezone, so this only matters for
reading logs. Logging goes to journald, which rotates itself; cap it with
`SystemMaxUse=` in `/etc/systemd/journald.conf` if the VPS disk is small.

Nothing needs to be reachable from outside, so the firewall can stay closed to
everything except SSH; the collector only makes outbound requests.

### Two collectors at once

Don't. Both would poll the same feeds twice as often for no extra information.
Once the VPS one is up, stop the local one.

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

## The approaches, and switching between them

Every design decision in the model is a claim that something is worth doing.
`config.py` turns each of them into a switch, so the claim can be checked
against a recording instead of argued about:

```
python3 -m lvivpred experiment                        # all of them
python3 -m lvivpred experiment --only full sections   # just these two
```

Each variant is replayed cold - no snapshot loaded, none saved - over the same
slice of `data/feed.db`, and all of them are then scored on the predictions
every one of them made. The results land in `reports/approaches.md` (readable)
and `reports/approaches.json` (per-bucket metrics with confidence intervals).

The nine variants are `full`, `no-prior`, `no-hold`, `no-corridor`, `no-fast`,
`no-incremental`, `sections`, `vehicle-offset` and `schedule-offset`; the report
explains what each one is. `reports/approaches.md` is checked in, so what the
model scored on a given day is part of the history rather than a memory.

## Documentation

`HANDOFF.md` is the entry point: what state the work is in, which document
answers which question, and what to do next. `PLAN.md` is the working plan for
the approach comparison and `reports/findings.md` is what the numbers turned out
to mean.

`docs/` describes the upstream feeds themselves - the realtime protobuf, the
static GTFS, the `api.lad.lviv.ua` JSON board, and the gotchas found in each.
