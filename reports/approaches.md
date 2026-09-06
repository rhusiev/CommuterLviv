# Approaches, and what each one scored

One recording: 80572 stop crossings over 1056 minutes of replay. Every approach is scored on the 1318685 predictions all of them made, so the numbers below answer the same questions.

`lad` is not in that support and not in these tables. It answers about only the 40 stops the collector polls, so intersecting over it too would judge every other approach on a small subsample chosen by which stops we happen to poll. It has its own table at the end, against the approaches it can be compared to.

A switch that scores better than `full` is a claim the shipped model makes and this recording does not support. Before acting on one, check the 95% intervals under `buckets` in `approaches.json` - the overall table has none, because a difference that only shows up pooled across every horizon is not one worth acting on. They are resampled over whole trips, and on a recording this short several of these gaps sit inside them.

## Overall, on the common support

| approach | MAE s | vs full | median s | RMSE s | bias s | <60 s | <120 s |
|---|---|---|---|---|---|---|---|
| no-prior | 114 | -5% | 64 | 205 | -61 | 48.0% | 70.3% |
| prior-shape | 118 | -1% | 65 | 210 | -18 | 47.5% | 69.5% |
| knn | 118 | -1% | 66 | 212 | -42 | 47.0% | 69.6% |
| full | 119 | - | 66 | 211 | -9 | 47.1% | 69.0% |
| offset-decay | 121 | +1% | 68 | 214 | -36 | 46.0% | 68.6% |
| sections | 121 | +1% | 67 | 214 | -52 | 46.3% | 68.6% |
| no-fast | 122 | +2% | 67 | 214 | -6 | 46.6% | 68.4% |
| no-incremental | 122 | +2% | 68 | 211 | +17 | 46.2% | 67.9% |
| sections-no-prior | 127 | +6% | 74 | 217 | -46 | 43.5% | 65.7% |
| no-hold | 130 | +9% | 73 | 221 | +26 | 44.0% | 65.6% |
| no-corridor | 132 | +11% | 73 | 225 | +22 | 43.9% | 65.5% |
| table-live | 134 | +12% | 75 | 232 | -52 | 43.3% | 65.1% |
| table | 134 | +13% | 75 | 231 | -20 | 43.2% | 64.9% |
| k-split | 140 | +17% | 78 | 235 | +24 | 42.3% | 63.2% |
| vehicle-offset | 163 | +36% | 95 | 265 | -105 | 37.3% | 57.1% |
| median | 174 | +46% | 105 | 277 | -146 | 34.5% | 54.0% |
| schedule-offset | 208 | +75% | 126 | 313 | +102 | 30.7% | 48.5% |
| api | 467 | +291% | 159 | 1328 | -74 | 26.4% | 42.8% |
| schedule | 860 | +621% | 625 | 1265 | +496 | 12.3% | 20.8% |

## MAE by how far ahead the prediction was

| approach | 0-1 min | 1-2 min | 2-5 min | 5-10 min | 10-20 min | 20-45 min |
|---|---|---|---|---|---|---|
| no-prior | 15 | 24 | 39 | 66 | 114 | 218 |
| prior-shape | 17 | 28 | 46 | 75 | 123 | 212 |
| knn | 18 | 30 | 46 | 75 | 120 | 216 |
| full | 17 | 29 | 47 | 77 | 126 | 212 |
| offset-decay | 16 | 27 | 45 | 76 | 127 | 219 |
| sections | 19 | 30 | 46 | 74 | 122 | 225 |
| no-fast | 17 | 29 | 47 | 78 | 128 | 216 |
| no-incremental | 18 | 30 | 49 | 80 | 131 | 212 |
| sections-no-prior | 18 | 29 | 47 | 78 | 131 | 231 |
| no-hold | 18 | 31 | 51 | 85 | 140 | 226 |
| no-corridor | 19 | 33 | 54 | 89 | 144 | 225 |
| table-live | 19 | 31 | 50 | 83 | 137 | 247 |
| table | 20 | 33 | 52 | 87 | 141 | 239 |
| k-split | 19 | 33 | 55 | 92 | 152 | 244 |
| vehicle-offset | 15 | 26 | 46 | 86 | 163 | 325 |
| median | 16 | 28 | 50 | 92 | 169 | 353 |
| schedule-offset | 27 | 51 | 86 | 146 | 238 | 340 |
| api | 297 | 314 | 347 | 404 | 486 | 607 |
| schedule | 806 | 807 | 813 | 827 | 865 | 920 |

## The public arrivals board, where it answers at all

The same events again, restricted to the 161466 predictions `lad` also made. Nothing here is comparable to the tables above - this is a different, much smaller set of events, and the three familiar approaches are repeated on it so that the board has something to be read against.

The board and `api` are both the operator's, and they are not the same quality: the board is several times the better of the two. Whatever produces it is doing more than replaying `trip_updates`. It is still beaten here, but by much less than the gap to `api` would suggest, and it is the harder of the two to beat.

| approach | MAE s | vs full | median s | RMSE s | bias s | <60 s | <120 s |
|---|---|---|---|---|---|---|---|
| full | 85 | - | 48 | 153 | -21 | 57.3% | 79.9% |
| lad | 111 | +31% | 63 | 178 | -42 | 48.0% | 72.0% |
| api | 408 | +382% | 107 | 1319 | -140 | 33.0% | 53.8% |
| schedule | 907 | +969% | 647 | 1301 | +562 | 8.4% | 14.4% |

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

### sections

Learn one travel time per stop-to-stop section rather than per 100 m cell. Corridor pooling is off because a section spans many corridors and cannot be assigned to one.

### sections-no-prior

Sections and no timetable prior together. Each alone beats the full model, and the measured reason is the same one - the prior's bias reaches a cell only where live evidence is thin - so the two gains may well be the same gain counted twice.

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
