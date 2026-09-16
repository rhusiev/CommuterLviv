# CommuterLviv

Live arrival times for Lviv's trams, trolleybuses and buses: when the next one
actually arrives, not when the timetable says it should.

The city publishes where its vehicles are. This project map-matches every fix
onto its trip's shape, learns how long each 100 m of road is taking right now,
and turns that into an arrival time for every stop ahead of every vehicle. At a
one-minute horizon its median error is 14 s against the official feed's 35 s,
and it lands inside a minute 93% of the time against 72%.

It is a server, a web app and an Android app, all on one version number.

```sh
cp .env.example .env      # a password, and the origin you serve on
docker compose up -d --build
docker compose exec service python -m commuterlviv admin invite
```

That prints one registration link. "Running the whole thing, in production"
below is the full version.

```
python3 -m commuterlviv serve     # the model, over HTTP and websockets
python3 -m commuterlviv collect   # record the live feeds into data/feed.db
python3 -m commuterlviv walk      # fetch the footpaths, for the journey planner
python3 -m commuterlviv plan      # door to door: walk, ride, walk
python3 -m commuterlviv admin     # invite links and accounts
```

The service needs `numpy`, `requests`, `protobuf` and what is in
`requirements-live.txt`. Everything it downloads or learns lives in `data/` and
is rebuilt on demand.

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

Take the copy while the collector is running with SQLite's own backup, not with
`scp`. The database is in WAL mode, so the newest rows are in `feed.db-wal` and
a plain copy of `feed.db` is both missing them and possibly torn:

Python does it, and there is no `sqlite3` command line tool on a machine that
only ever runs the collector:

```sh
ssh vps python3 <<'EOF'
import sqlite3
sqlite3.connect("/opt/commuterlviv/data/feed.db").backup(
    sqlite3.connect("/tmp/feed-snapshot.db"))
EOF
ssh vps gzip -9 /tmp/feed-snapshot.db            # it compresses about 4:1
scp vps:/tmp/feed-snapshot.db.gz .
```

Inside the stack, the same, through the image's own python:

```sh
docker compose exec -T service python -c "import sqlite3; \
  sqlite3.connect('data/feed.db').backup(sqlite3.connect('data/snapshot.db'))"
docker compose cp service:/app/data/snapshot.db ./feed-snapshot.db
docker compose exec -T service rm /app/data/snapshot.db
```

The snapshot is as large as the recording, so delete it once it is copied - the
collector stops at 3 GB free.

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

`GET /api/plan?from=lat,lon&to=lat,lon` answers the door-to-door question:
walk, ride, maybe change, walk, ranked by arrival, with the whole walk offered
as one of the options. It is RAPTOR (Delling, Pajor, Werneck 2012) over the
GTFS timetable, three rounds so at most two changes, with footpaths from an
OpenStreetMap walking graph rather than straight lines. There is no hardcoded
radius for which stops count as nearby: the bound is the time to walk the whole
way, because a walk longer than that can never be part of a better journey.

A tracked vehicle enters the search as an ordinary one-trip pattern built from
its own predictions, so where the model has something to say it outranks the
schedule automatically, and past the model's 45-minute horizon there simply are
no live trips left and the timetable takes over with no rule needed. Every ride
leg carries `live: true` or `false`, and both clients label it, because
somebody deciding whether to run for a bus deserves to know which of the two
they are reading. How much accuracy is lost at the far end of that horizon is
still unmeasured - it needs the VPS recording.

Every ride also carries a `confidence`, which is what the schedule is worth on
that route right now. `live` is a vehicle being tracked. `schedule` is the
timetable on a route that is running. `quiet` is the timetable on a route the
schedule wanted at least twice in the last hour and nothing has been seen on
since - a line the city is not running today, which the timetable alone will
happily promise you a bus from. A `quiet` ride is held back unless it is the
only ride on offer, in which case it is returned and flagged: an unreliable bus
is worth knowing about, an invented one is not.

The options are ranked by a front over arrival time, number of changes and
seconds spent walking, so a slower journey with one change fewer survives
alongside the fastest, and every option that does not beat simply walking the
way is dropped. `&at=<unix seconds>` plans a trip that starts later instead of
now. A later departure still rides the vehicles being tracked - only their
arrivals that lie ahead of it are kept - so nothing is thrown away at some
cutoff; past the model's 45 minute horizon there are none left and the timetable
takes over on its own.

`GET /api/traffic/streets` and `GET /api/traffic` are the same numbers the
model uses for its ETAs, drawn as a map: per 100 m of track, the ratio of how
long vehicles are actually taking to how long the timetable expects. A stretch
too little has crossed lately comes back as `null` and is not drawn - the model
would happily hand back the corridor's number there, which is a fair ETA and a
meaningless traffic reading.

The numbers are pooled before they are drawn. A unit belongs to one route's
shape, so a street ten routes run down carries ten units, each with its own
number and its own idea of where the kerb is; drawn as they are, that is ten
near-parallel lines crossing each other. They are pooled on `Shape.corridor` -
the key the model already pools evidence on, a 120 m box of the city crossed on
one of eight headings - which turns 25,625 stretches into 5,867 lines, one per
piece of street per direction of travel, coloured by the weighted mean of the
units in it. The one split kept is tram against road: a tram on its own track is
not in the traffic the buses are in, while a trolleybus is on the road with them
and is pooled with them. The geometry is 55 KB gzipped, fixed for the life of the
process and cached by ETag; the ratios come separately, in the same order, and
are built and serialised once every 30 s rather than per request, since the
clients poll every minute and the numbers move slower than that.

Two hundred metres at either end of every shape are left out entirely. A vehicle
at a terminus crawls in, parks, and crawls out, and the crawling is rolling time
over cells whose timetabled pace is short, so the ratio there is high on every
route in the city - which is a layover and not traffic. That drops 1087 of the
26,712 units the model learns. Only that shape's own units go: a route running
past another's terminus still pools its own view of the street.

Neither client draws the stretches one at a time. The phone projects them once,
at zoom 18, and gathers them into one path per colour, so a frame is a couple of
dozen `drawPath` calls under a single transform and panning re-projects nothing;
the browser hands maplibre one GeoJSON source and replaces its data only when
new numbers arrive. Both push each line to the right of its own travel, so the
two directions of a street sit side by side rather than one hiding the other.

`GET /api/search?q=` finds addresses and places by name, which the catalog
cannot: it is Photon over OpenStreetMap, biased to the city and clamped to it,
with answers cached for a day so typing costs one request per new prefix.
`COMMUTERLVIV_PHOTON_URL` points it at a self-hosted instance, and emptying it
turns the feature off and leaves searching to stop names.

The planner needs two caches that are built once and are not in the image:

```sh
python3 -m commuterlviv walk         # data/walk.npz, the OSM footpath graph
python3 -m commuterlviv plan --build # data/transfers.npz, stop-to-stop on foot
```

`walk.npz` is pure OpenStreetMap and can be copied between hosts; `transfers.npz`
indexes stops by the catalog it was built against and must be rebuilt wherever
`network.pkl` differs. Without them the service still starts, logs why, and
`/api/plan` answers 503 - the map and the arrivals do not depend on it.

`GET /api/shapes` is where a route physically goes: per route, the polylines its
trips follow, each marked with the feed direction it runs. Direction is drawn by
the clients, not served - a run both ways gets two tracks of chevrons, one per
side, spaced on screen rather than on the ground, which is why nothing here has
to be respaced per zoom. 245 KB, 33 KB gzipped, one ETag for the life of the process, and both clients ask for it
only the first time something wants to draw a line - tapping a vehicle's badge
to see its route, or the button that puts the whole network on the map. Nobody
who opens neither pays for it.

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
map is yours. `docker compose logs -f service` is the rest of the interface,
with `admin users`, `admin disable <name>` and `admin delete <name> --yes`
beside it - `disable` locks an account and ends its sessions and can be undone,
`delete` erases it and everything hanging off it and cannot.

`admin operator <name>` is the fourth, and it grants one thing: the right to
read `GET /api/status`, which reports engine health, how many clients are
connected and how much the service is pushing. Being signed in does not carry
that - to anyone without the flag the endpoint is a 404, so it does not even
admit to being there. `--undo` takes it back.

**One version, three trees.** `commuterlviv/__init__.py` holds it, `web/package.json`
and `mobile/pubspec.yaml` repeat it, and `check.sh` fails if they drift; the
service reports it at `/api/health`, so what is deployed is a question with an
answer. It goes up with every substantial change and stays under 1.0 while this
is alpha - and the Android `versionCode` goes up with it, because F-Droid
orders releases by that alone.

**The phone app is on F-Droid.** `deploy/release-apk.sh` builds the three
per-ABI APKs the same way F-Droid does and prints the `gh release create`
command that puts them on the GitHub release page; F-Droid downloads them
back, rebuilds from source, and refuses to publish unless the bytes match.

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

**Behind a proxy that is already running**, publish nothing at all. The third
overlay drops the host port and puts the web container on the proxy's own
docker network instead, so the proxy reaches it by name and the stack has no
door to the outside:

```sh
echo 'CADDY_NETWORK=caddy' >> .env      # the existing network's name
docker compose -f docker-compose.yml -f docker-compose.proxy.yml up -d
```

```caddy
commuterlviv.example.com {
	reverse_proxy commuterlviv_web:8080
}
```

That is the whole of it: `/ws` is an ordinary upgrade through the same
`reverse_proxy` and needs no separate rule, and the outer proxy holds the
certificate so `docker-compose.tls.yml` is not used with this. The outer proxy
has to be on that network too. Rate limits stay per real client because Caddy
sets `X-Forwarded-For` and the service reads the first entry - which is also
why `COMMUTERLVIV_TRUST_PROXY` must stay off for a deployment where the port is
reachable directly.

### Moving it to a machine that is already collecting

The repository has no remote, so the checkout is what travels. Everything the
stack needs is in it except two gitignored things worth carrying by hand: the
recording and the walking graph.

```sh
rsync -a --delete --exclude data --exclude node_modules --exclude build \
      --exclude .git ./ vps:/opt/commuterlviv/app/
scp .env vps:/opt/commuterlviv/app/.env          # then fix ORIGINS on the far side
scp data/walk.npz vps:/opt/commuterlviv/walk.npz
```

`walk.npz` is pure OpenStreetMap and host-independent, so copying it saves an
Overpass fetch; `transfers.npz` is not - it is numbered against the catalog it
was built with, so it is always built on the far side.

**Stop the old collector before starting the new one.** Two collectors poll the
same feeds twice for no extra information. The recording moves into the volume
the stack uses, and then the systemd unit is retired:

```sh
sudo systemctl disable --now commuterlviv
docker compose up -d --build db service          # creates the volume
docker compose cp /opt/commuterlviv/data/feed.db service:/app/data/feed.db
docker compose cp /opt/commuterlviv/walk.npz service:/app/data/walk.npz
docker compose up -d                             # the collector joins in
docker compose exec service python -m commuterlviv plan --build
docker compose exec service python -m commuterlviv admin invite
```

Copying the recording in is not housekeeping: a restart replays its last two
hours to warm the model, and a service that starts without one spends twenty
minutes making the worst predictions it ever makes.

**What it reaches out to, and what that costs you.** Four hosts, and only one of
them is unavoidable:

| Host | Who asks | How often | Doing without it |
| --- | --- | --- | --- |
| `track.ua-gis.com` | the service and the collector | every 5 s | nothing to do - this *is* the data |
| `tiles.versatiles.org` | every phone and browser, per tile | while the map moves | `docker-compose.tiles.yml` serves the basemap from the stack instead - see below |
| `overpass-api.de` | the service | once per volume, ever | `COMMUTERLVIV_BUILD_PLANNER=false` and copy `data/walk.npz` in |
| `api.lad.lviv.ua` | the collector only | every 5 s | `--profile collect` is off by default; the served app never touches it |

The one worth thinking about is the tile server, not Overpass. Overpass is asked
once, in the background, for a 5 MB file that is then a file - no request a user
makes ever waits on it, and the whole dependency ends the moment `walk.npz`
exists. The basemap is the opposite: it is a request per tile, from every
device, for as long as anyone pans the map, and it is the only third party your
users talk to directly.

**Serving the basemap yourself.** One script and one overlay:

```sh
deploy/tiles-setup.sh https://commuterlviv.example.org /opt/commuterlviv/tiles
COMMUTERLVIV_TILES=/opt/commuterlviv/tiles \
  docker compose -f docker-compose.yml -f docker-compose.tiles.yml up -d
```

The script cuts a Lviv extract out of the 66 GB planet over HTTP range requests
- about 20 MB at maxzoom 14 - fetches the sprites and glyphs, and generates the
five styles. It wants the address because a style names its sprite, glyph and
tile URLs absolutely, and the phone's style reader does not resolve relative
ones. That address is the only place this deployment writes its own name down.

Neither app is built knowing any of it. The overlay sets
`COMMUTERLVIV_SELF_TILES`, the service reports it on `/api/health`, and the web
app and the phone app both ask before they draw a map - so one web image and one
APK work under any domain, and pointing the phone at a different deployment
follows that deployment's map too.

Worth knowing:

- **The collector runs in the stack.** It writes `data/feed.db` in a volume,
  keeps 30 days and stops if the disk drops below 3 GB. It is not optional
  scenery: a restart replays the last two hours of it to warm the model, and
  without that the first twenty minutes after every restart are the worst
  predictions the service ever makes.
- **First boot takes a couple of minutes.** The static GTFS feed has to be
  fetched and the city's geometry built from it. Both are cached in the same
  volume, so every boot after that is seconds.
- **The journey planner builds itself on first boot**, in a background task, so
  `/api/plan` is a 503 for the two or three minutes it takes and everything else
  serves normally. It happens once, because the result is two files in the
  volume. To do it by hand instead - or to keep the deployment off Overpass
  entirely - set `COMMUTERLVIV_BUILD_PLANNER=false` and either copy
  `data/walk.npz` and `data/transfers.npz` in, or run
  `docker compose exec service python -m commuterlviv walk` and then
  `... plan --build`.
- **`COMMUTERLVIV_SECURE_COOKIES` defaults to true** and browsers only accept
  `__Host-` cookies over HTTPS. Serving over plain HTTP with it left on gives a
  login that silently never sticks.
- **The compose project is named `commuterlviv`**, so the volumes are
  `commuterlviv_postgres_data` and `commuterlviv_service_data` whatever the checkout
  directory is called. An older checkout that ran compose from `main/` has its
  database in `main_postgres_data`; that volume is now unused.

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
arrival for each, and pinning it puts it in the Times tab. Clicking a vehicle
asks the opposite question: `GET /api/vehicle?veh=<id>` answers with every stop
that vehicle is predicted to reach and when, out to the model's 45-minute
horizon, read off the same predictions the stop card shows - so the two cannot
disagree. A third tab plans a journey: tap where you are and where you are
going, and it answers with ways to get there, ranked by arrival - walk to a
stop, ride, maybe change, walk to the door. Named sets of routes -
one for work, one for home - live on the server, so they follow the account
rather than the browser. Serve `dist/` with a history fallback: every path has to
return `index.html`, or `/join/<code>` is a 404 and the invite link is dead.

One palette, two clients. `web/src/app.css` declares five colours, two radii and
one shadow in a Tailwind `@theme` block, and `mobile/lib/src/theme.dart` repeats
the same values; two of the colours, the near-black plate and the sky accent,
are the two colours in `web/public/icon.svg`, so both apps are the colour of
their own icon. Above that sit the utilities everything is built from - `panel`,
`bar`, `fab`, `inset-panel`, `btn`, `btn-quiet`, `field`, `field-bar` - and each
is translucent, blurred, a hairline ring and a soft shadow rather than a border,
because the map underneath is the context. Nothing outside `app.css` names a
`slate-*` shade for a surface.

Nothing is docked to an edge. The map is the whole window in both clients and
every piece of chrome floats over it: a search bar and a menu at the top, the
map/times/plan pill at the bottom where a thumb is, round buttons for locate and
zoom, and cards that rise off the bottom rather than out of it. That is why the
web layout is one `relative` box of absolutely positioned pieces instead of a
column, and why the phone's `Scaffold` has neither an `appBar` nor a
`bottomNavigationBar`: `floatingTop` and `floatingBottom` in `theme.dart` are
what anything scrollable uses to clear the two floating bars.

What goes where is decided by what a control does, not by how often it is
wanted. Routes choose what is tracked and open the routes panel. Layers change
what the map draws - the route lines, the traffic, the basemap - and live in one
sheet behind a layers button, whose icon is lit while anything in it is on.
Everything belonging to the account rather than to the map - what is saved, the
language, the server, signing out - lives behind an account button, with signing
out below a rule so it is never the tap next to anything else. Nothing that is a
toggle and nothing that signs you out sits loose on the map. That is
`LayersSheet` and `AccountSheet` in `mobile/lib/src/sheets.dart`, and
`LayersPanel.tsx` and `AccountMenu.tsx` on the web.

A route is named the same way everywhere: the kind of vehicle as a glyph, then
the number. The city writes the kind as the letter in front of the number - `А25`
is a bus, `Т07` a tram, `Тр33` a trolleybus - which only helps a reader who knows
that and reads Cyrillic, so `routeNumber` in `web/src/lib/sprites.ts` and
`mobile/lib/src/map_theme.dart` strips it and `RouteBadge` draws it instead. The
glyphs are three line drawings in `RouteBadge.tsx` and `route_badge.dart`, the
same 24-unit box in both, because no icon set carries a trolleybus. On the map
there is no room for a glyph in a 26 px circle, so the badge is the number alone
and the hue carries the kind - which it already did.

`tool/icons.sh` draws every icon of all three clients from that one SVG,
including the `maskable` PNG the manifest points at, which is framed like the
Android adaptive icon because a browser crops it.

It installs. `web/public/manifest.webmanifest` and `web/public/sw.js` make it a
progressive web app: an icon on the home screen, no browser chrome, and a shell
that opens without the network. The worker caches only what it has already
served - hashed assets under `/assets/` for good, the document network-first -
and never `/api` or `/ws`, because a minute-old arrival time is worse than none
and a cached session would lie about who is signed in. Offline it opens and says
the service is not answering, which is the truth: the times come from the socket.

The language is Ukrainian, with English for a browser that asks for it;
`web/src/lib/i18n.ts` holds both dictionaries and the picker is in the route
panel. Changing it reloads the page; the phone app, which shares the same keys,
switches without a restart.

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
route sets and the same predictions, and the same journey planner behind the
third choice in the tab pill. Both also carry the same three views added since:
a saved list where a place can be renamed or dropped, a search that finds
addresses and shops as well as stop names, and traffic drawn over the streets
the model can see.

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
The one cost of that rule is paid by the locate-me button, which is a
hand-written channel - AOSP's `LocationManager` on Android, `CoreLocation` on
iOS - rather than the usual package, which brings Play Services with it; see
`mobile/README.md`. The app asks for the internet permission, and
for location on the first press of that button; the fix never leaves the
phone.

The service needs one line for it: `app://commuterlviv` in `COMMUTERLVIV_ORIGINS`. The
app is not a web page and has no web origin, and that scheme is one no browser
will ever mint, so listing it cannot widen what a web page may do.

