# Approaches, and what each one scored

One recording: 93796 stop crossings over 1143 minutes of replay. Every approach is scored on the 1756722 predictions all of them made, so the numbers below answer the same questions.

`lad` is not in that support and not in these tables. It answers about only the 40 stops the collector polls, so intersecting over it too would judge every other approach on a small subsample chosen by which stops we happen to poll. It has its own table at the end, against the approaches it can be compared to.

A switch that scores better than `full` is a claim the shipped model makes and this recording does not support. Before acting on one, check the 95% intervals under `buckets` in `approaches.json` - the overall table has none, because a difference that only shows up pooled across every horizon is not one worth acting on. They are resampled over whole trips, and on a recording this short several of these gaps sit inside them.

## Overall, on the common support

| approach | MAE s | vs full | median s | RMSE s | bias s | <60 s | <120 s |
|---|---|---|---|---|---|---|---|
| tuned | 114 | -5% | 61 | 206 | -66 | 49.3% | 70.6% |
| no-prior | 115 | -4% | 65 | 206 | -63 | 47.7% | 69.7% |
| prior-shape | 119 | -1% | 65 | 210 | -19 | 47.4% | 69.2% |
| full | 120 | - | 66 | 212 | -10 | 46.9% | 68.7% |
| knn | 121 | +0% | 67 | 215 | -40 | 46.4% | 68.9% |
| sections | 122 | +1% | 68 | 215 | -53 | 46.2% | 68.3% |
| offset-decay | 122 | +1% | 69 | 215 | -38 | 45.6% | 68.1% |
| no-fast | 123 | +2% | 68 | 214 | -7 | 46.4% | 68.0% |
| no-incremental | 123 | +2% | 68 | 212 | +18 | 46.0% | 67.7% |
| sections-no-prior | 128 | +6% | 75 | 218 | -50 | 43.2% | 65.2% |
| no-hold | 131 | +9% | 74 | 222 | +27 | 43.7% | 65.3% |
| no-corridor | 132 | +9% | 74 | 224 | +20 | 43.8% | 65.5% |
| k-split | 140 | +17% | 77 | 235 | +23 | 42.5% | 63.4% |
| table-live | 144 | +20% | 82 | 242 | -40 | 40.6% | 62.0% |
| table | 149 | +24% | 85 | 246 | -5 | 39.8% | 60.9% |
| vehicle-offset | 165 | +37% | 97 | 267 | -109 | 36.8% | 56.4% |
| median | 177 | +47% | 108 | 280 | -150 | 33.9% | 53.3% |
| schedule-offset | 199 | +66% | 119 | 304 | +89 | 31.9% | 50.4% |
| api | 471 | +292% | 147 | 1406 | -105 | 27.7% | 44.7% |
| schedule | 843 | +601% | 579 | 1268 | +431 | 13.2% | 22.4% |

## MAE by how far ahead the prediction was

| approach | 0-1 min | 1-2 min | 2-5 min | 5-10 min | 10-20 min | 20-45 min |
|---|---|---|---|---|---|---|
| tuned | 15 | 24 | 39 | 65 | 111 | 223 |
| no-prior | 15 | 25 | 40 | 67 | 114 | 221 |
| prior-shape | 17 | 29 | 46 | 76 | 123 | 213 |
| full | 18 | 30 | 48 | 78 | 126 | 214 |
| knn | 19 | 31 | 48 | 76 | 122 | 219 |
| sections | 19 | 30 | 47 | 75 | 122 | 227 |
| offset-decay | 16 | 27 | 46 | 77 | 127 | 221 |
| no-fast | 18 | 30 | 48 | 79 | 129 | 217 |
| no-incremental | 18 | 31 | 50 | 81 | 132 | 213 |
| sections-no-prior | 18 | 30 | 47 | 79 | 132 | 234 |
| no-hold | 19 | 32 | 52 | 86 | 141 | 227 |
| no-corridor | 20 | 33 | 54 | 89 | 143 | 225 |
| k-split | 19 | 34 | 55 | 93 | 151 | 244 |
| table-live | 20 | 34 | 56 | 93 | 150 | 258 |
| table | 21 | 36 | 60 | 99 | 160 | 258 |
| vehicle-offset | 16 | 27 | 47 | 87 | 165 | 330 |
| median | 16 | 28 | 50 | 93 | 171 | 359 |
| schedule-offset | 27 | 50 | 84 | 141 | 226 | 324 |
| api | 305 | 321 | 352 | 406 | 485 | 618 |
| schedule | 789 | 791 | 795 | 807 | 843 | 912 |

## The public arrivals board, where it answers at all

The same events again, restricted to the 212763 predictions `lad` also made. Nothing here is comparable to the tables above - this is a different, much smaller set of events, and the three familiar approaches are repeated on it so that the board has something to be read against.

The board and `api` are both the operator's, and they are not the same quality: the board is several times the better of the two. Whatever produces it is doing more than replaying `trip_updates`. It is still beaten here, but by much less than the gap to `api` would suggest, and it is the harder of the two to beat.

| approach | MAE s | vs full | median s | RMSE s | bias s | <60 s | <120 s |
|---|---|---|---|---|---|---|---|
| full | 87 | - | 49 | 158 | -22 | 56.6% | 79.1% |
| lad | 114 | +30% | 65 | 182 | -50 | 47.0% | 71.1% |
| api | 429 | +391% | 104 | 1437 | -184 | 33.5% | 54.5% |
| schedule | 914 | +947% | 622 | 1330 | +499 | 8.8% | 15.7% |

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
