# Approaches, and what each one scored

One recording: 129684 stop crossings over 1360 minutes of replay. Every approach is scored on the 2537566 predictions all of them made, so the numbers below answer the same questions.

`lad` is not in that support and not in these tables. It answers about only the 40 stops the collector polls, so intersecting over it too would judge every other approach on a small subsample chosen by which stops we happen to poll. It has its own table at the end, against the approaches it can be compared to.

A switch that scores better than `full` is a claim the shipped model makes and this recording does not support. Before acting on one, check the 95% intervals under `buckets` in `approaches.json` - the overall table has none, because a difference that only shows up pooled across every horizon is not one worth acting on. They are resampled over whole trips, and on a recording this short several of these gaps sit inside them.

## Overall, on the common support

| approach | MAE s | vs full | median s | RMSE s | bias s | <60 s | <120 s |
|---|---|---|---|---|---|---|---|
| no-prior | 112 | -5% | 64 | 199 | -58 | 48.1% | 70.2% |
| slow-day | 113 | -4% | 62 | 201 | -51 | 49.0% | 70.5% |
| tuned | 113 | -4% | 62 | 201 | -68 | 49.0% | 70.3% |
| full | 118 | - | 67 | 205 | -7 | 46.8% | 68.9% |
| api | 548 | +364% | 150 | 1916 | -188 | 27.2% | 44.1% |
| schedule | 877 | +643% | 605 | 1303 | +424 | 12.4% | 21.1% |

## MAE by how far ahead the prediction was

| approach | 0-1 min | 1-2 min | 2-5 min | 5-10 min | 10-20 min | 20-45 min |
|---|---|---|---|---|---|---|
| no-prior | 16 | 25 | 40 | 66 | 111 | 207 |
| slow-day | 16 | 25 | 40 | 66 | 111 | 209 |
| tuned | 15 | 24 | 38 | 64 | 109 | 215 |
| full | 18 | 29 | 47 | 76 | 123 | 203 |
| api | 383 | 398 | 424 | 472 | 546 | 708 |
| schedule | 821 | 823 | 827 | 837 | 868 | 952 |

## The public arrivals board, where it answers at all

The same events again, restricted to the 305928 predictions `lad` also made. Nothing here is comparable to the tables above - this is a different, much smaller set of events, and the three familiar approaches are repeated on it so that the board has something to be read against.

The board and `api` are both the operator's, and they are not the same quality: the board is several times the better of the two. Whatever produces it is doing more than replaying `trip_updates`. It is still beaten here, but by much less than the gap to `api` would suggest, and it is the harder of the two to beat.

| approach | MAE s | vs full | median s | RMSE s | bias s | <60 s | <120 s |
|---|---|---|---|---|---|---|---|
| full | 86 | - | 49 | 153 | -21 | 56.5% | 79.2% |
| lad | 117 | +36% | 68 | 185 | -58 | 45.6% | 69.6% |
| api | 493 | +472% | 106 | 1868 | -248 | 33.5% | 54.0% |
| schedule | 940 | +992% | 666 | 1326 | +521 | 8.1% | 14.3% |

## What each approach is

### full

The model as it ships: everything below turned on.

### slow-day

A third half-life of one day beneath the other two, at both the cell and the corridor scale. The city runs no service between 00:00 and 05:30, so by 06:00 the 5400 s term has decayed to 1.2% of the blend and the model opens the morning peak back on the timetable - finding 6 measures it believing the city 15% slower than it is. This asks whether what a cell was doing yesterday is a better opening guess than the schedule.

### no-prior

Learn pace itself instead of a multiplier on the timetable's. Costs the model everything the schedule knows about where and when the city is slow, so every cell must be learned from live data alone.

### tuned

The shipped model at the best value each of its four constants found when swept alone. Every one of those sweeps moved the same way - less shrinkage, longer memory - and the four gains do add: this is the only variant that beats the shipped model at every horizon out to 20 minutes. It pays for that in the 20-45 minute bucket, where trusting live evidence sooner and forgetting it later carries the current state of the road much further ahead than it holds.

### api

The operator's own `trip_updates` feed, replayed from the recorded change log at our epochs.

### lad

The arrivals board at api.lad.lviv.ua that the public is shown. Only the stops the collector polls appear in it.

### schedule

The static timetable with no real-time input at all, as a floor.
