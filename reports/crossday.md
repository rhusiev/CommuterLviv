# The same approaches, day by day

One replay per approach over the whole recording - 717685 crossings, 5739 minutes - cut afterwards by the service day each prediction was made on. The models are not restarted at the day boundaries: whatever an online approach learns on one day it carries into the next, which is the point of the table.

**2026-09-05 is the cold day.** Nothing was carried into it, so it is the only column that asks the question a one-day recording could ask. Read every later column against it: an approach whose lead disappears once the others have seen a day of the city was winning the cold start and not the road.

The support is the crossings and instants every approach answered, chosen once over the whole recording and then cut by day, so the columns are comparable to each other.

| approach | 2026-09-05 | 2026-09-06 | 2026-09-07 | 2026-09-08 | 2026-09-09 |
|---|---|---|---|---|---|
| _predictions_ | 160404 | 2915776 | 4233260 | 4422164 | 3723154 |
| profile | 122 | 112 | 139 | 137 | 144 |
| profile-no-prior | 109 | 110 | 142 | 139 | 147 |
| full | 133 | 116 | 141 | 141 | 149 |
| prior-shape | 126 | 115 | 141 | 142 | 150 |
| no-prior | 111 | 112 | 143 | 143 | 153 |
| knn | 125 | 120 | 141 | 142 | 152 |
| no-incremental | 146 | 120 | 144 | 142 | 151 |
| no-fast | 138 | 118 | 144 | 144 | 152 |
| offset-decay | 125 | 118 | 145 | 147 | 155 |
| tuned | 107 | 113 | 153 | 147 | 155 |
| slow-day | 118 | 112 | 155 | 149 | 156 |
| sections | 113 | 119 | 149 | 151 | 160 |
| no-corridor | 146 | 127 | 149 | 150 | 157 |
| no-hold | 159 | 128 | 152 | 152 | 159 |
| sections-no-prior | 126 | 124 | 153 | 155 | 163 |
| k-split | 156 | 140 | 158 | 159 | 166 |
| table-live | 122 | 146 | 183 | 192 | 199 |
| table | 124 | 149 | 200 | 208 | 220 |
| schedule-offset | 173 | 196 | 196 | 202 | 202 |
| vehicle-offset | 155 | 167 | 202 | 206 | 216 |
| median | 151 | 183 | 218 | 225 | 239 |
| schedule | 540 | 869 | 870 | 862 | 921 |
| api | 202 | 645 | 558 | 1987 | 2476 |

MAE in seconds. `crossday.json` holds the 95% intervals, which are resampled over whole trips within each day and are wide enough that a gap of a second or two between two approaches on one day is not a fact about them.
