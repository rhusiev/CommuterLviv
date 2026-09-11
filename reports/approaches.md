# Approaches, and what each one scored

One recording: 717685 stop crossings over 5739 minutes of replay. Every approach is scored on the 15454758 predictions all of them made, so the numbers below answer the same questions.

`lad` is not in that support and not in these tables. It answers about only the 40 stops the collector polls, so intersecting over it too would judge every other approach on a small subsample chosen by which stops we happen to poll. It has its own table at the end, against the approaches it can be compared to.

A switch that scores better than `full` is a claim the shipped model makes and this recording does not support. Before acting on one, check the 95% intervals under `buckets` in `approaches.json` - the overall table has none, because a difference that only shows up pooled across every horizon is not one worth acting on. They are resampled over whole trips, and on a recording this short several of these gaps sit inside them.

## Overall, on the common support

| approach | MAE s | vs full | median s | RMSE s | bias s | <60 s | <120 s |
|---|---|---|---|---|---|---|---|
| profile | 134 | -3% | 74 | 226 | -64 | 44.0% | 64.9% |
| profile-no-prior | 136 | -1% | 75 | 229 | -86 | 43.7% | 64.4% |
| full | 138 | - | 79 | 228 | -35 | 42.0% | 63.2% |
| prior-shape | 138 | +0% | 78 | 229 | -46 | 42.3% | 63.4% |
| no-prior | 139 | +1% | 77 | 232 | -81 | 42.7% | 63.3% |
| knn | 140 | +1% | 82 | 229 | -47 | 40.8% | 62.3% |
| no-incremental | 141 | +2% | 83 | 225 | +13 | 40.4% | 61.5% |
| no-fast | 141 | +2% | 80 | 231 | -33 | 41.4% | 62.4% |
| offset-decay | 143 | +3% | 82 | 234 | -67 | 40.7% | 62.0% |
| tuned | 144 | +4% | 77 | 241 | -93 | 43.0% | 63.1% |
| slow-day | 145 | +5% | 77 | 242 | -92 | 42.9% | 62.9% |
| sections | 146 | +6% | 82 | 240 | -74 | 40.7% | 61.8% |
| no-corridor | 147 | +6% | 86 | 236 | -11 | 39.3% | 60.4% |
| no-hold | 149 | +8% | 90 | 235 | +24 | 38.3% | 58.9% |
| sections-no-prior | 150 | +9% | 87 | 244 | -76 | 39.3% | 59.9% |
| k-split | 157 | +13% | 92 | 247 | +4 | 37.9% | 58.2% |
| table-live | 182 | +32% | 108 | 285 | -80 | 33.6% | 53.2% |
| table | 196 | +42% | 115 | 307 | -110 | 32.7% | 51.4% |
| schedule-offset | 199 | +44% | 125 | 299 | +12 | 29.9% | 48.8% |
| vehicle-offset | 199 | +44% | 121 | 304 | -154 | 32.1% | 49.7% |
| median | 218 | +58% | 135 | 329 | -196 | 29.6% | 46.6% |
| schedule | 876 | +534% | 624 | 1296 | +428 | 9.5% | 16.9% |
| api | 1442 | +943% | 163 | 9278 | -1133 | 24.8% | 41.5% |

## MAE by how far ahead the prediction was

| approach | 0-1 min | 1-2 min | 2-5 min | 5-10 min | 10-20 min | 20-45 min |
|---|---|---|---|---|---|---|
| profile | 17 | 28 | 44 | 74 | 125 | 240 |
| profile-no-prior | 16 | 26 | 42 | 71 | 123 | 250 |
| full | 18 | 30 | 49 | 82 | 135 | 237 |
| prior-shape | 18 | 30 | 48 | 80 | 133 | 240 |
| no-prior | 16 | 27 | 43 | 74 | 128 | 253 |
| knn | 19 | 33 | 52 | 84 | 136 | 238 |
| no-incremental | 19 | 32 | 53 | 87 | 143 | 231 |
| no-fast | 18 | 31 | 50 | 83 | 138 | 241 |
| offset-decay | 16 | 28 | 47 | 82 | 138 | 248 |
| tuned | 16 | 26 | 42 | 73 | 129 | 267 |
| slow-day | 16 | 26 | 43 | 74 | 130 | 269 |
| sections | 20 | 32 | 50 | 81 | 135 | 260 |
| no-corridor | 20 | 34 | 55 | 92 | 148 | 243 |
| no-hold | 20 | 33 | 55 | 92 | 153 | 245 |
| sections-no-prior | 19 | 31 | 49 | 83 | 141 | 267 |
| k-split | 20 | 35 | 57 | 97 | 159 | 259 |
| table-live | 22 | 38 | 64 | 108 | 176 | 312 |
| table | 21 | 37 | 63 | 109 | 184 | 351 |
| schedule-offset | 27 | 50 | 82 | 135 | 209 | 312 |
| vehicle-offset | 16 | 27 | 49 | 94 | 181 | 378 |
| median | 17 | 29 | 54 | 102 | 192 | 419 |
| schedule | 874 | 873 | 871 | 870 | 873 | 886 |
| api | 824 | 826 | 843 | 884 | 1079 | 2469 |

## MAE by the hour of day the prediction was made

Hours with fewer than 300 paired predictions are left out. The counts are of predictions, not crossings, and a crossing is predicted about once a minute until it happens, so an hour with few vehicles running still carries many rows.

| approach | 05:00 | 06:00 | 07:00 | 08:00 | 09:00 | 10:00 | 11:00 | 12:00 | 13:00 | 14:00 | 15:00 | 16:00 | 17:00 | 18:00 | 19:00 | 20:00 | 21:00 | 22:00 | 23:00 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| _predictions_ | 11813 | 451985 | 1022871 | 1182224 | 1189671 | 1066116 | 1033961 | 981868 | 967589 | 975587 | 1066038 | 1134512 | 1140983 | 1108569 | 919842 | 647800 | 444839 | 101350 | 7140 |
| profile | 300 | 135 | 159 | 220 | 132 | 114 | 112 | 114 | 116 | 117 | 118 | 120 | 163 | 145 | 113 | 129 | 118 | 87 | 55 |
| profile-no-prior | 161 | 112 | 165 | 232 | 134 | 111 | 112 | 116 | 120 | 121 | 124 | 124 | 169 | 149 | 109 | 122 | 108 | 82 | 51 |
| full | 325 | 173 | 160 | 208 | 136 | 127 | 120 | 118 | 118 | 118 | 118 | 119 | 156 | 143 | 125 | 148 | 138 | 97 | 60 |
| prior-shape | 304 | 165 | 160 | 213 | 136 | 124 | 119 | 118 | 119 | 119 | 119 | 121 | 160 | 146 | 122 | 143 | 132 | 95 | 60 |
| no-prior | 171 | 126 | 169 | 237 | 134 | 115 | 114 | 118 | 121 | 123 | 125 | 125 | 172 | 151 | 113 | 130 | 116 | 85 | 51 |
| knn | 120 | 122 | 161 | 186 | 139 | 134 | 128 | 130 | 131 | 132 | 130 | 129 | 157 | 148 | 136 | 134 | 115 | 86 | 63 |
| no-incremental | 351 | 186 | 153 | 178 | 143 | 150 | 136 | 126 | 120 | 117 | 116 | 116 | 138 | 134 | 148 | 171 | 161 | 114 | 73 |
| no-fast | 326 | 182 | 164 | 214 | 139 | 130 | 123 | 120 | 119 | 119 | 119 | 121 | 158 | 145 | 128 | 152 | 142 | 99 | 61 |
| offset-decay | 279 | 157 | 164 | 218 | 140 | 125 | 123 | 123 | 126 | 127 | 127 | 129 | 169 | 153 | 120 | 138 | 124 | 92 | 58 |
| tuned | 151 | 124 | 148 | 250 | 150 | 112 | 112 | 119 | 123 | 127 | 131 | 133 | 188 | 176 | 111 | 126 | 116 | 87 | 55 |
| slow-day | 156 | 128 | 148 | 248 | 153 | 112 | 112 | 118 | 123 | 128 | 132 | 135 | 191 | 180 | 112 | 126 | 117 | 87 | 55 |
| sections | 192 | 136 | 174 | 238 | 145 | 125 | 123 | 123 | 127 | 130 | 130 | 132 | 177 | 159 | 121 | 136 | 120 | 91 | 57 |
| no-corridor | 340 | 202 | 166 | 212 | 150 | 140 | 131 | 125 | 124 | 123 | 123 | 124 | 159 | 150 | 139 | 159 | 151 | 107 | 64 |
| no-hold | 364 | 196 | 158 | 179 | 154 | 159 | 144 | 136 | 130 | 127 | 126 | 125 | 142 | 143 | 161 | 184 | 174 | 127 | 84 |
| sections-no-prior | 194 | 144 | 179 | 248 | 150 | 126 | 125 | 126 | 132 | 133 | 135 | 136 | 182 | 163 | 122 | 140 | 125 | 92 | 52 |
| k-split | 310 | 181 | 171 | 202 | 157 | 154 | 147 | 143 | 140 | 139 | 137 | 138 | 160 | 155 | 156 | 182 | 173 | 122 | 75 |
| table-live | 178 | 140 | 183 | 246 | 198 | 174 | 172 | 170 | 174 | 175 | 173 | 178 | 211 | 203 | 155 | 155 | 132 | 108 | 68 |
| table | 168 | 151 | 190 | 289 | 216 | 178 | 175 | 175 | 180 | 184 | 186 | 193 | 245 | 237 | 159 | 154 | 137 | 107 | 68 |
| schedule-offset | 260 | 235 | 203 | 251 | 210 | 197 | 195 | 186 | 181 | 177 | 177 | 179 | 211 | 207 | 185 | 206 | 198 | 143 | 75 |
| vehicle-offset | 175 | 165 | 212 | 272 | 202 | 179 | 184 | 184 | 193 | 196 | 195 | 199 | 239 | 222 | 163 | 166 | 139 | 118 | 76 |
| median | 217 | 162 | 227 | 301 | 212 | 194 | 203 | 206 | 216 | 221 | 216 | 220 | 263 | 239 | 178 | 179 | 150 | 131 | 88 |
| schedule | 588 | 712 | 727 | 720 | 817 | 893 | 931 | 1004 | 1062 | 1026 | 936 | 913 | 895 | 873 | 914 | 828 | 633 | 379 | 165 |
| api | 3275 | 1571 | 1176 | 1063 | 1088 | 1419 | 1629 | 1852 | 1951 | 1714 | 1692 | 1614 | 1710 | 1375 | 1319 | 976 | 468 | 324 | 133 |

## The public arrivals board, where it answers at all

The same events again, restricted to the 1162415 predictions `lad` also made. Nothing here is comparable to the tables above - this is a different, much smaller set of events, and the three familiar approaches are repeated on it so that the board has something to be read against.

The board and `api` are both the operator's, and they are not the same quality: the board is several times the better of the two. Whatever produces it is doing more than replaying `trip_updates`. It is still beaten here, but by much less than the gap to `api` would suggest, and it is the harder of the two to beat.

| approach | MAE s | vs full | median s | RMSE s | bias s | <60 s | <120 s |
|---|---|---|---|---|---|---|---|
| full | 101 | - | 58 | 169 | -33 | 51.0% | 73.4% |
| lad | 134 | +32% | 79 | 208 | -65 | 40.7% | 64.4% |
| api | 560 | +453% | 115 | 3363 | -348 | 31.4% | 51.2% |
| schedule | 940 | +828% | 670 | 1338 | +488 | 7.3% | 13.3% |

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
