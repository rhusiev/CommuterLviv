# How it works

**How does a GPS fix from the city's feed become a predicted arrival time at a
stop, and how do we know the prediction is any good?**

The trace below follows one position fix from the moment it arrives to the
moment its prediction is scored. Every step names the file it happens in.

## 1. A fix arrives, roughly every 10 seconds per vehicle

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

## 2. The fix is placed on a line, not a map

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
`data/network.pkl` on the next start, because the cache is keyed by
`network.source()`, a digest of the feed and this file both.
`check_overrides.py` on the `development-archive` branch builds from scratch and
asserts every rule still lands where it says.

Each shape is also cut into 100 m **cells**, and each cell is tagged with a
**corridor** key: which 120 m ground square it sits in, and which of 8 compass
octants it points along. Two routes driving the same street the same way land
in the same corridor even though they are different shapes. That is how
evidence gets pooled across routes.

## 3. The fix is folded into a filter, not used directly

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

## 4. The interval since the last fix is charged to the road

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

## 5. The road updates the model, once a minute

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

The service runs the `profile` variant (`COMMUTERLVIV_VARIANT`, `config.py`),
which puts one more layer between the cell and its corridor: per cell, one
weighted mean per hour of the day (`pr`, 24 of them), with a one-week half-life
(`prof_hl`, 604800 s). It is what this cell did at this hour on the days before.
So a cell backs off from its live means to its own hour-of-day history, then to
the corridor, then to the network. That is what carries the city across the
overnight gap: by 06:00 the 5400 s means have decayed to nothing, and without
the profile the morning peak would open on the timetable alone.

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

## 6. An ETA is a subtraction

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

## 7. Truth is measured, not assumed

Steps 7 and 8 are the evaluation. Its code - `truth.py`, `predictors.py`,
`score.py` and the reports - lives on the `development-archive` branch; `dev`
and `main` carry only what serves.

`track.py` records the moment each stop was actually passed, by interpolating
between the two fixes either side of it. `truth.py` then keeps only the
**unambiguous** crossings: an event is dropped if the same (trip, stop) or the
same (vehicle, stop) occurs more than once in the window, since then no
predictor's naming can be matched to it without guessing.

The yardstick's own precision is checked and reported: the interval a crossing
was interpolated across is 16 s at the median, 52 s at p90, 299 s at worst. That
is well below the differences being measured, so the comparison is measuring
predictors and not the feed.

## 8. Four predictors are scored on identical support

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

Starting warm is worth measuring too. A replay that starts from the model
learned so far instead of from the timetable covers 98.2% of truth instead of
90.5%, and its 0-1 minute MAE drops from 22 s to 17 s. The service keeps its
model on disk for that reason - see
[the model across restarts](service.md#the-model-across-restarts).
