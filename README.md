# CommuterLviv

Arrival-time prediction for Lviv public transport, and a measurement of how it
compares with the city's own.

```
python3 -m commuterlviv collect      # record the live feeds into data/feed.db
python3 -m commuterlviv evaluate     # replay what was recorded and score everything
python3 -m commuterlviv experiment   # score every approach on the same recording
python3 -m commuterlviv check        # model, tracking or truth: which one is wrong
python3 -m commuterlviv diag         # what methodology is the official API using
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

The stop list comes from the feed, and the feed is occasionally missing one: a
route drives past a stop, calls at it, and is absent from that stop's
`stop_times` rows, so the stop has no times for that route anywhere - not here
and not on the city's own board. `commuterlviv/overrides.toml` is where such a
stop is put back, one rule at a time:

```toml
[[add]]
route = "А16"                     # the short name, as a rider reads it
stop = "0711"                     # the code on the sign
toward = "Приміський вокзал"      # which direction's platform this is
```

`overrides.py` folds each rule in before any distance is solved, so an added
stop is an ordinary stop from then on: placed by the same Viterbi pass, given a
scheduled time interpolated between its neighbours for each trip separately,
and listed in the catalogue because the catalogue is built from the stop lists.
A rule only applies to patterns whose line passes within 50 m, `within` moves
that, and `toward` - matched against the last stop's name - is what keeps a
one-way platform off the pattern going the other way. Editing the file rebuilds
`data/network.pkl` on the next start, because `network.fresh()` compares the
cache against the feed and this file both. `python3 check_overrides.py` builds
from scratch and asserts every rule still lands where it says.

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
| an override stops applying, because the feed now lists the stop | the rule is skipped with a line on stderr, and the build carries on |

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
sudo adduser --system --group --home /opt/commuterlviv commuterlviv
sudo -u commuterlviv git clone <this repo> /opt/commuterlviv
cd /opt/commuterlviv
sudo -u commuterlviv python3 -m venv .venv
sudo -u commuterlviv .venv/bin/pip install -r requirements.txt

sudo cp deploy/commuterlviv.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now commuterlviv
```

Then:

```sh
systemctl status commuterlviv          # is it up
journalctl -u commuterlviv -f          # the heartbeat line, live
journalctl -u commuterlviv --since -1d | grep -c error
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
python3 -m commuterlviv experiment                        # all of them
python3 -m commuterlviv experiment --only full sections   # just these two
```

Each variant is replayed cold - no snapshot loaded, none saved - over the same
slice of `data/feed.db`, and all of them are then scored on the predictions
every one of them made. The results land in `reports/approaches.md` (readable)
and `reports/approaches.json` (per-bucket metrics with confidence intervals).

The nine variants are `full`, `no-prior`, `no-hold`, `no-corridor`, `no-fast`,
`no-incremental`, `sections`, `vehicle-offset` and `schedule-offset`; the report
explains what each one is. `reports/approaches.md` is checked in, so what the
model scored on a given day is part of the history rather than a memory.

## Serving it live

The same model, on wall time instead of a recording, is `commuterlviv/live/` behind
`python3 -m commuterlviv serve`. It polls the vehicle feed every five seconds, folds
each fix into the same tracks, steps the model on the same 60 s grid, and pushes
positions per poll and arrivals per epoch over a websocket. It shares the code
rather than resembling it: one epoch in the service is the same four calls
`replay._flush` makes offline, in the same order, so the numbers it serves are
the numbers the reports measured.

```sh
pip install -r requirements-live.txt
export COMMUTERLVIV_DATABASE_URL=postgresql://commuterlviv:...@127.0.0.1:5432/commuterlviv
export COMMUTERLVIV_ORIGINS=https://commuterlviv.r1a.nl,app://commuterlviv   # the web app, and the phone app
export COMMUTERLVIV_WEB_BASE=https://commuterlviv.r1a.nl     # optional; defaults to the first origin
export COMMUTERLVIV_VARIANT=slow-day                 # which predictor answers
python3 -m commuterlviv admin invite                 # a registration link, printed once
python3 -m commuterlviv serve
```

Accounts are required for everything except `/api/health`, for two reasons,
neither of them capacity. They carry a person's named route sets and pinned
stops between their devices, both stored as feed ids so that a rebuilt catalog
cannot quietly move them. And a watching client costs only bytes - the model runs once for the
whole city - so what the gate protects is not the CPU but the output: a tracked,
smoothed, city-wide vehicle history, handed over at 228 B/s to anyone who opens
the socket. Passwords are argon2id, sessions are opaque rows in Postgres behind
a `__Host-` cookie, and remember-me is series+token rotated on every use, where
a spent token coming back is treated as theft. Migrations apply themselves at
boot and there is no down direction. The socket is not signed in once and
trusted forever: it re-asks about its session every minute and closes with 4401
when it has gone, it takes five messages a second with a burst of sixty, and it
hangs up on a client that spends 500 messages past that.

Registration is `COMMUTERLVIV_REGISTRATION=open|code|closed`, `code` by default.
Under `code` there is no way in without a link an admin minted: `admin invite`
prints `<web base>/join/<code>` once, the web app posts it to
`/api/register/{code}`, and only the code's SHA-256 is stored - so a lost link
is gone rather than recoverable. Under `open` the same request without a code,
to `/api/register`, is accepted. Both clients read the setting from
`/api/health` before anyone is signed in and show what it allows: an invite
field, a sign-up button, or neither. It is on the public endpoint because there
is no one to ask when the question is asked, and because it is not a secret -
whether a service takes new accounts is answered by trying.

## Running the whole thing, in production

Four containers - Postgres, the service, the collector that feeds it, and Caddy
in front - and one command.

```sh
cp .env.example .env      # then edit it: a password, and the origin you serve on
docker compose up -d --build
docker compose exec service python -m commuterlviv admin invite
```

That last line prints one registration link. Open it, pick a username, and the
map is yours. `docker compose logs -f service` is the rest of the interface.

Two lines of `.env` decide everything and neither has a safe guess:
`POSTGRES_PASSWORD`, and `COMMUTERLVIV_ORIGINS` - the exact origins allowed to make
unsafe requests, scheme and host and port, no trailing slash. Everything else in
the file is commented out with its default beside it.

**Caddy serves the app and the service on one origin**, passing `/api` and `/ws`
back and serving `index.html` for every other path. One origin is what makes the
`__Host-` session cookies work with no cross-origin rules at all, and the
`index.html` fallback is what keeps `/join/<code>` from being a 404.

By default Caddy is published on `127.0.0.1:8080`, on the assumption that this
machine already has something terminating TLS. If it does not, and the domain
points here, hand Caddy the domain and it gets a certificate itself:

```sh
echo 'COMMUTERLVIV_SITE_ADDRESS=commuterlviv.r1a.nl' >> .env
docker compose -f docker-compose.yml -f docker-compose.tls.yml up -d
```

Worth knowing:

- **The collector runs in the stack.** It writes `data/feed.db` in a volume,
  keeps 30 days and stops if the disk drops below 3 GB. It is not optional
  scenery: a restart replays the last two hours of it to warm the model, and
  without that the first twenty minutes after every restart are the worst
  predictions the service ever makes.
- **First boot takes a couple of minutes.** The static GTFS feed has to be
  fetched and the city's geometry built from it. Both are cached in the same
  volume, so every boot after that is seconds.
- **`COMMUTERLVIV_SECURE_COOKIES` defaults to true** and browsers only accept
  `__Host-` cookies over HTTPS. Serving over plain HTTP with it left on gives a
  login that silently never sticks.
- **The compose project is named `commuterlviv`**, so the volumes are
  `commuterlviv_postgres_data` and `commuterlviv_service_data` whatever the checkout
  directory is called. An older checkout that ran compose from `main/` has its
  database in `main_postgres_data`; that volume is now unused.

## Running the whole thing, in development

The same stack with the source mounted, the UI on Vite's dev server, and the
ports open:

```sh
cp .env.example .env      # the password still has to be something
docker compose -f docker-compose.yml -f docker-compose.dev.yml up
```

Then `http://localhost:5173` for the app, `:8099` for the service directly,
`:5432` for Postgres and `:5050` for pgadmin. Editing anything under `web/`
reloads in the browser; editing anything under `commuterlviv/` needs
`docker compose restart service`, because the service holds a model in memory
that a reloader would throw away every keystroke.

The dev overlay sets `COMMUTERLVIV_DEV=true`, which turns the secure-cookie
requirement off, and lists `http://localhost:5173`, `http://127.0.0.1:5173` and
`app://commuterlviv` as origins. Those two spellings of localhost are different
origins and the service is right to refuse a mismatch, so both are named.

Not using containers is still one command each: `python3 -m commuterlviv serve` and
`npm run dev` in `web/`, against any Postgres. The compose file exists to make
the first run easy, not to become the only way in.

## The map

`web/` is what you look at: React 19 and Vite, a canvas of vehicles over a
MapLibre basemap.

```sh
cd web && npm install
npm run dev      # http://localhost:5173, proxying /api and /ws to the service
npm run build    # dist/, 69 kB gzipped, static, plus a lazy 265 kB of MapLibre
npm run preview  # http://localhost:5174, the built files with the same proxy
```

Lviv itself is MapLibre GL JS drawing VersaTiles' `shadow` style over
OpenStreetMap vector tiles - no key and no account, and `VITE_MAP_STYLE` points
it somewhere else if that host ever goes away.

Vehicles are coloured circles carrying their route number, with a wedge on the
rim pointing where they are going - solid while the vehicle is under way, an
outline while it stands, so a marker always says which way it faces without
claiming it is moving. Stops are small circles, drawn only for the routes you
have picked. Clicking one lists every route through it with the next
arrival for each, and pinning it puts it in the Times tab. Named sets of routes -
one for work, one for home - live on the server, so they follow the account
rather than the browser. Serve `dist/` with a history fallback: every path has to
return `index.html`, or `/join/<code>` is a 404 and the invite link is dead.

It installs. `web/public/manifest.webmanifest` and `web/public/sw.js` make it a
progressive web app: an icon on the home screen, no browser chrome, and a shell
that opens without the network. The worker caches only what it has already
served - hashed assets under `/assets/` for good, the document network-first -
and never `/api` or `/ws`, because a minute-old arrival time is worse than none
and a cached session would lie about who is signed in. Offline it opens and says
the service is not answering, which is the truth: the times come from the socket.

The language is Ukrainian, with English for a browser that asks for it;
`web/src/lib/i18n.ts` holds both dictionaries and the picker is in the route
panel. Changing it reloads the page.

Smoothness is the reason for the shape of the code. Positions arrive every five
seconds, and between them each vehicle is interpolated towards where the server
last put it, eased over 1.2 s, with the heading taking the short way round.
Nothing about a position passes through React: the socket writes into a plain
`Map`, the animation loop reads it, and React only ever hears about the
connection, the arrivals and the vehicle count. Route badges are rendered once
into offscreen canvases, so drawing four hundred vehicles is four hundred blits
rather than four hundred text layouts. The overlay draws inside MapLibre's own
render pass and projects points with the same Web Mercator formula the basemap
uses, so panning moves the city and the vehicles in the same frame.

## The phone

`mobile/` is the same client again, in Flutter, for Android and iOS. It adds no
endpoint and no model - the browser and the phone see the same city, the same
route sets and the same predictions.

```sh
cd mobile && flutter pub get
flutter test     # the wire decoder, against bytes commuterlviv/live/wire.py made
flutter run --dart-define=COMMUTERLVIV_BASE=http://10.0.2.2:8099
flutter build apk --release
```

Without that `--dart-define` the app talks to `https://commuterlviv.r1a.nl`, which is
where it is published: an F-Droid build passes no defines, so the default has to
be the real server. The sign-in screen takes any other address and remembers it.

The shape of the code is the shape of the web app's, for the same reason. Every
vehicle and every stop is one `CustomPaint` repainted from a `Ticker`, not four
hundred widgets; positions are eased between the five-second frames; and the
route badge for each route is laid out once into a `ui.Paragraph` and drawn
thereafter, which is what the offscreen badge canvases do in the browser.

It is built to be publishable on F-Droid, which is why it is Flutter and not
Expo: F-Droid builds from source and takes no proprietary SDK, so there is no
Play Services, no Firebase and no keyed map SDK anywhere in the tree. The
basemap is the same VersaTiles OpenStreetMap tiles, rendered on the device.
The one cost of that rule is that there is no locate-me button yet - see
`mobile/README.md`. The app asks for the internet permission and nothing else.

The service needs one line for it: `app://commuterlviv` in `COMMUTERLVIV_ORIGINS`. The
app is not a web page and has no web origin, and that scheme is one no browser
will ever mint, so listing it cannot widen what a web page may do.

## Documentation

`HANDOFF.md` is the entry point: what state the work is in, which document
answers which question, and what to do next. `PLAN.md` is the working plan for
the approach comparison and `reports/findings.md` is what the numbers turned out
to mean.

`docs/` describes the upstream feeds themselves - the realtime protobuf, the
static GTFS, the `api.lad.lviv.ua` JSON board, and the gotchas found in each.
