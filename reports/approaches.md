# Approaches, and what each one scored

One recording: 8672 unambiguous stop crossings over 232 minutes of replay. Every approach is scored on the 16462 predictions all of them made, so the numbers below answer the same questions.

A switch that scores better than `full` is a claim the shipped model makes and this recording does not support. Before acting on one, check the 95% intervals in `approaches.json`: they are resampled over whole trips, and on a recording this short several of these gaps sit inside them.

## Overall, on the common support

| approach | MAE s | vs full | median s | RMSE s | bias s | <60 s | <120 s |
|---|---|---|---|---|---|---|---|
| no-prior | 109 | -12% | 64 | 173 | -9 | 47.9% | 70.0% |
| sections | 118 | -5% | 69 | 188 | -13 | 45.8% | 68.1% |
| full | 124 | - | 70 | 194 | +36 | 45.3% | 66.1% |
| no-fast | 127 | +2% | 72 | 198 | +41 | 44.8% | 65.6% |
| no-incremental | 132 | +6% | 78 | 202 | +59 | 42.6% | 64.0% |
| no-hold | 141 | +13% | 87 | 212 | +69 | 38.9% | 60.9% |
| no-corridor | 143 | +15% | 82 | 222 | +56 | 40.1% | 62.3% |
| vehicle-offset | 144 | +16% | 85 | 222 | -53 | 40.5% | 60.3% |
| schedule-offset | 166 | +33% | 103 | 249 | +55 | 34.1% | 55.4% |
| api | 224 | +80% | 114 | 410 | -24 | 30.3% | 51.5% |
| lad | 375 | +201% | 90 | 980 | -337 | 38.2% | 58.3% |
| schedule | 729 | +486% | 406 | 1230 | -47 | 8.5% | 18.5% |

## MAE by how far ahead the prediction was

| approach | 0-1 min | 1-2 min | 2-5 min | 5-10 min | 10-20 min | 20-45 min |
|---|---|---|---|---|---|---|
| no-prior | 24 | 38 | 58 | 91 | 139 | 304 |
| sections | 26 | 42 | 64 | 100 | 148 | 325 |
| full | 29 | 48 | 73 | 112 | 153 | 319 |
| no-fast | 29 | 48 | 74 | 114 | 156 | 330 |
| no-incremental | 30 | 50 | 77 | 119 | 164 | 330 |
| no-hold | 31 | 53 | 82 | 129 | 176 | 343 |
| no-corridor | 29 | 51 | 81 | 128 | 175 | 391 |
| vehicle-offset | 24 | 38 | 63 | 108 | 202 | 408 |
| schedule-offset | 33 | 58 | 96 | 155 | 203 | 426 |
| api | 130 | 139 | 158 | 200 | 227 | 615 |
| lad | 96 | 102 | 117 | 147 | 359 | 2398 |
| schedule | 729 | 729 | 734 | 750 | 702 | 755 |

## What each approach is

### full

The model as it ships: everything below turned on.

### no-prior

Learn pace itself instead of a multiplier on the timetable's. Costs the model everything the schedule knows about where and when the city is slow, so every cell must be learned from live data alone.

### no-hold

One quantity instead of two: standing time is folded into pace and scales with distance. This is what a speed-per-section model does implicitly.

### no-corridor

A cell backs off straight to one city-wide number, never to the street it is on. Tests whether pooling across routes that share a road is worth anything.

### no-fast

Only the 5400 s half-life term. The model still knows this street, but not what traffic is doing on it right now.

### no-incremental

A crossing is reported only once finished. Fast crossings then report before slow ones, so the model hears about a jam after it has cleared.

### sections

Learn one travel time per stop-to-stop section rather than per 100 m cell. Corridor pooling is off because a section spans many corridors and cannot be assigned to one.

### vehicle-offset

The full road model, then scaled by how fast this particular vehicle has been running against it. Asks whether anything is left in the vehicle after the road is accounted for.

### schedule-offset

Not a road model at all: the timetable plus this vehicle's current lateness, held constant to the end of the trip. This is what the official API was measured to be doing, reimplemented here so it can be scored on exactly the same events.

### api

The operator's own `trip_updates` feed, replayed from the recorded change log at our epochs.

### lad

The arrivals board at api.lad.lviv.ua that the public is shown. Only the stops the collector polls appear in it.

### schedule

The static timetable with no real-time input at all, as a floor.
