# Approaches, and what each one scored

One recording: 717685 stop crossings over 5739 minutes of replay. Every approach is scored on the 15519766 predictions all of them made, so the numbers below answer the same questions.

`lad` is not in that support and not in these tables. It answers about only the 40 stops the collector polls, so intersecting over it too would judge every other approach on a small subsample chosen by which stops we happen to poll. It has its own table at the end, against the approaches it can be compared to.

A switch that scores better than `full` is a claim the shipped model makes and this recording does not support. Before acting on one, check the 95% intervals under `buckets` in `approaches.json` - the overall table has none, because a difference that only shows up pooled across every horizon is not one worth acting on. They are resampled over whole trips, and on a recording this short several of these gaps sit inside them.

## Overall, on the common support

| approach | MAE s | vs full | median s | RMSE s | bias s | <60 s | <120 s |
|---|---|---|---|---|---|---|---|
| profile | 134 | -3% | 74 | 226 | -64 | 44.0% | 64.9% |
| profile-no-prior | 136 | -1% | 75 | 229 | -86 | 43.7% | 64.3% |
| full | 138 | - | 79 | 228 | -35 | 42.0% | 63.1% |
| prior-shape | 139 | +0% | 78 | 230 | -45 | 42.3% | 63.4% |
| no-prior | 139 | +1% | 77 | 232 | -81 | 42.7% | 63.3% |
| knn | 140 | +1% | 82 | 230 | -47 | 40.7% | 62.2% |
| no-incremental | 141 | +2% | 83 | 225 | +13 | 40.4% | 61.5% |
| no-fast | 141 | +2% | 80 | 232 | -32 | 41.4% | 62.4% |
| offset-decay | 143 | +3% | 82 | 234 | -66 | 40.7% | 61.9% |
| tuned | 144 | +4% | 77 | 241 | -92 | 43.0% | 63.1% |
| slow-day | 145 | +5% | 77 | 243 | -91 | 42.9% | 62.9% |
| sections | 146 | +6% | 82 | 241 | -74 | 40.7% | 61.8% |
| no-corridor | 147 | +6% | 86 | 236 | -11 | 39.3% | 60.4% |
| no-hold | 149 | +8% | 90 | 235 | +24 | 38.3% | 58.9% |
| sections-no-prior | 150 | +9% | 87 | 244 | -76 | 39.3% | 59.9% |
| k-split | 157 | +13% | 92 | 248 | +4 | 37.9% | 58.2% |
| schedule-offset | 199 | +44% | 125 | 299 | +12 | 29.9% | 48.8% |
| vehicle-offset | 199 | +44% | 121 | 304 | -154 | 32.1% | 49.7% |
| table-live | 207 | +49% | 126 | 318 | -119 | 29.9% | 48.4% |
| table | 209 | +51% | 128 | 317 | -26 | 29.6% | 48.0% |
| median | 218 | +57% | 135 | 329 | -196 | 29.6% | 46.6% |
| schedule | 875 | +533% | 623 | 1295 | +427 | 9.5% | 16.9% |
| api | 1432 | +935% | 163 | 9240 | -1124 | 24.9% | 41.6% |

## MAE by how far ahead the prediction was

| approach | 0-1 min | 1-2 min | 2-5 min | 5-10 min | 10-20 min | 20-45 min |
|---|---|---|---|---|---|---|
| profile | 17 | 28 | 44 | 74 | 125 | 240 |
| profile-no-prior | 16 | 26 | 42 | 71 | 123 | 251 |
| full | 18 | 30 | 49 | 82 | 135 | 237 |
| prior-shape | 18 | 30 | 48 | 80 | 133 | 241 |
| no-prior | 16 | 27 | 43 | 74 | 128 | 254 |
| knn | 19 | 33 | 52 | 84 | 136 | 239 |
| no-incremental | 19 | 32 | 53 | 88 | 143 | 231 |
| no-fast | 18 | 31 | 50 | 83 | 138 | 242 |
| offset-decay | 16 | 28 | 47 | 82 | 138 | 248 |
| tuned | 16 | 26 | 42 | 73 | 129 | 268 |
| slow-day | 16 | 26 | 43 | 74 | 130 | 269 |
| sections | 20 | 32 | 50 | 82 | 135 | 260 |
| no-corridor | 20 | 34 | 55 | 92 | 148 | 243 |
| no-hold | 20 | 33 | 55 | 93 | 153 | 246 |
| sections-no-prior | 19 | 31 | 49 | 84 | 141 | 267 |
| k-split | 20 | 35 | 57 | 97 | 159 | 259 |
| schedule-offset | 27 | 49 | 82 | 135 | 209 | 312 |
| vehicle-offset | 16 | 27 | 49 | 94 | 181 | 378 |
| table-live | 22 | 40 | 69 | 118 | 198 | 363 |
| table | 25 | 46 | 78 | 133 | 213 | 343 |
| median | 17 | 29 | 54 | 102 | 192 | 419 |
| schedule | 873 | 872 | 870 | 869 | 872 | 885 |
| api | 820 | 822 | 840 | 880 | 1075 | 2450 |

## The public arrivals board, where it answers at all

The same events again, restricted to the 1170417 predictions `lad` also made. Nothing here is comparable to the tables above - this is a different, much smaller set of events, and the three familiar approaches are repeated on it so that the board has something to be read against.

The board and `api` are both the operator's, and they are not the same quality: the board is several times the better of the two. Whatever produces it is doing more than replaying `trip_updates`. It is still beaten here, but by much less than the gap to `api` would suggest, and it is the harder of the two to beat.

| approach | MAE s | vs full | median s | RMSE s | bias s | <60 s | <120 s |
|---|---|---|---|---|---|---|---|
| full | 101 | - | 58 | 169 | -33 | 51.0% | 73.4% |
| lad | 134 | +32% | 79 | 207 | -65 | 40.7% | 64.5% |
| api | 558 | +450% | 115 | 3351 | -345 | 31.4% | 51.3% |
| schedule | 939 | +825% | 669 | 1336 | +487 | 7.3% | 13.3% |

## What each approach is

### full

The model as it ships: everything below turned on.

### no-prior

Learn pace itself instead of a multiplier on the timetable's. Costs the model everything the schedule knows about where and when the city is slow, so every cell must be learned from live data alone.

### prior-shape

Keep the timetable as a shape but not as a level: the same relative map of where and when the city is slow, rescaled so its own average pace is a constant and the level is learned like `no-prior` learns it. Tests whether the prior's measured 6% slow bias is the whole of what it costs.

### no-hold

One quantity instead of two: standing time is folded into pace and scales with distance. This is what a speed-per-section model does implicitly.

### no-corridor

A cell backs off straight to one city-wide number, never to the street it is on. Tests whether pooling across routes that share a road is worth anything.

### no-fast

Only the 5400 s half-life term. The model still knows this street, but not what traffic is doing on it right now.

### no-incremental

A crossing is reported only once finished. Fast crossings then report before slow ones, so the model hears about a jam after it has cleared.

### k-split

One shrinkage constant for both layers is measured to be the wrong shape: a cell is crossed 11.5 times a day and its fast term supplies 8% of the blend, while a corridor has ten times the evidence and is shrunk just as hard. This trusts the corridor sooner and the cell later.

### tuned

The shipped model at the best value each of its four constants found when swept alone. Every one of those sweeps moved the same way - less shrinkage, longer memory - and the four gains do add: this is the only variant that beats the shipped model at every horizon out to 20 minutes. It pays for that in the 20-45 minute bucket, where trusting live evidence sooner and forgetting it later carries the current state of the road much further ahead than it holds.

### slow-day

A third half-life of one day beneath the other two, at both the cell and the corridor scale. The city runs no service between 00:00 and 05:30, so by 06:00 the 5400 s term has decayed to 1.2% of the blend and the model opens the morning peak back on the timetable - finding 6 measures it believing the city 15% slower than it is. This asks whether what a cell was doing yesterday is a better opening guess than the schedule.

### profile

What this cell does at this hour, learned across days and kept for weeks, put where the corridor used to be: the thing the live terms fall back on when they have nothing. Finding 6 measures the model opening the morning peak believing the city 15% slower than it is, because the overnight gap decays every live term away and leaves only the timetable. `slow-day` carries yesterday across that gap as one number per cell; this carries yesterday's *morning* into this morning, which is the difference that matters if the city's slowness is a shape over the day rather than a level.

### profile-no-prior

The same profile with the timetable removed, so the hour-of-day pattern has to be learned rather than inherited. This is the literal form of finding 6's remedy - a learned profile instead of the schedule's - and the pair with `profile` says whether the schedule still adds anything once the model has its own history of the same hours.

### sections

Learn one travel time per stop-to-stop section rather than per 100 m cell. Corridor pooling is off because a section spans many corridors and cannot be assigned to one.

### sections-no-prior

Sections and no timetable prior together. Dropping the prior alone beats the full model and coarsening to sections alone does not, so this asks whether the one gain survives the other change. It does not: the pair scores worse than either.

### vehicle-offset

The full road model, then scaled by how fast this particular vehicle has been running against it. Asks whether anything is left in the vehicle after the road is accounted for.

### offset-decay

The same vehicle correction, but faded out along the path instead of applied flat. A vehicle's speed ratio is measured to persist about 4.5 minutes, so each leg of the trip is corrected only by what is left of that ratio by the time the vehicle gets there.

### table

No online learning at all: one pace and one hold per section per hour of the day, fitted during the warmup and then frozen. The historical average every transit paper starts from. What separates it from `full` is the whole value of learning as fixes arrive - so run it with a warmup that is a real training window, an evening scored the next morning.

### table-live

The frozen table times one online number: how fast today is running against it, city-wide. One parameter of live learning instead of tens of thousands, so what separates it from `table` is the value of knowing today is slow and nothing else.

### knn

The median of the last 10 crossings of this section by any vehicle, with no corridor, no global fallback and no half-life. Tests the back-off hierarchy against a plain recency window, and the mean against the median - MAE is minimised by the median, which nothing else here uses.

### median

The same three layers, the same two half-lives, the same two shrinkage constants - and a weighted median wherever the shipped model takes a mean. MAE is minimised by the median, so if the model is optimising the wrong loss this is what it costs. The price is memory: a median needs the last 16 crossings of a key kept, not one running number.

### schedule-offset

Not a road model at all: the timetable plus this vehicle's current lateness, held constant to the end of the trip. This is what the official API was measured to be doing, reimplemented here so it can be scored on exactly the same events.

### api

The operator's own `trip_updates` feed, replayed from the recorded change log at our epochs.

### lad

The arrivals board at api.lad.lviv.ua that the public is shown. Only the stops the collector polls appear in it.

### schedule

The static timetable with no real-time input at all, as a floor.
