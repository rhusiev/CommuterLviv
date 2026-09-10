# The same approaches, day by day

One replay per approach over the whole recording - 717685 crossings, 5739 minutes - cut afterwards by the service day each prediction was made on. The models are not restarted at the day boundaries: whatever an online approach learns on one day it carries into the next, which is the point of the table.

**2026-09-05 is the cold day.** Nothing was carried into it, so it is the only column that asks the question a one-day recording could ask. Read every later column against it: an approach whose lead disappears once the others have seen a day of the city was winning the cold start and not the road.

The support is the crossings and instants every approach answered, chosen once over the whole recording and then cut by day, so the columns are comparable to each other.

| approach | 2026-09-05 | 2026-09-06 | 2026-09-07 | 2026-09-08 | 2026-09-09 |
|---|---|---|---|---|---|
| _predictions_ | 162278 | 2940299 | 4280186 | 4498235 | 3788628 |
| full | 137 | 117 | 142 | 143 | 150 |
| no-prior | 113 | 113 | 144 | 144 | 153 |
| knn | 127 | 120 | 142 | 143 | 153 |
| tuned | 109 | 113 | 154 | 148 | 156 |
| slow-day | 120 | 112 | 155 | 150 | 156 |
| table | 126 | 150 | 200 | 210 | 221 |
| schedule | 544 | 873 | 871 | 865 | 923 |
| api | 205 | 707 | 575 | 2485 | 2939 |

MAE in seconds. `crossday.json` holds the 95% intervals, which are resampled over whole trips within each day and are wide enough that a gap of a second or two between two approaches on one day is not a fact about them.
