# Why the approaches scored what they did

`approaches.md` says which variants won. It does not say why, and five of the
results contradicted a claim the model makes about itself. Each one below was
measured on the same recording - 18.6 hours of `data/feed.db`, 245 307 cell
crossings over 19 228 distinct cells - not argued from the code.

The scripts behind these numbers were one-off instrumentation of `replay.run`,
not checked in. What is checked in is the conclusion and the number that
supports it.

## 1. The timetable prior costs 12% MAE, and it is not close

`model.py` claims the prior earns its place twice: it knows where the city is
slow, and it knows when. Neither holds.

**It does not know when.** Averaged over the network and weighted by cell
length, the prior's implied speed is 17.6 km/h at every hour of the day - the
24 hourly values run from 17.5 to 17.8. And 21 408 of the 26 712 cells have an
*identical* prior at all 24 hours, because no trip on that shape had a usable
timing in more than one hour slot. Four fifths of the network has no
time-of-day prior at all, and the fifth that does averages out to nothing.

**It barely knows where.** The correlation between log timetabled pace and log
observed pace, over the crossings actually seen, is 0.283. It explains 8% of
the variation it was introduced to explain.

**Dividing by it makes the learning problem harder, not easier.** This is the
number that settles it. Length-weighted standard deviation of the log of what
each variant has to learn:

| quantity | sd of log |
|---|---|
| `log(pace)` - what `no-prior` learns | 0.612 |
| `log(pace / prior)` - what `full` learns | 0.709 |

The prior adds noise worth 0.128 in variance while removing 8% of the signal.
The docstring's "a far smaller and far more poolable quantity" is false on this
data: it is 16% larger.

**And it biases the answer slow.** At the end of a replay, the model's believed
pace against the observed pace, length-weighted:

| variant | believed city speed | observed | mean log error |
|---|---|---|---|
| `full` | 18.6 km/h | 19.8 km/h | +0.1425 |
| `no-prior` | 19.8 km/h | 19.8 km/h | +0.1108 |

`full` believes the city is 6% slower than it is, which is +70 s on a 20-minute
ETA and matches its +36 s overall bias. The mechanism is a double count.
`_schedule_prior` builds an *effective* pace from stop-to-stop scheduled times,
so it already contains the scheduled dwell and the timetable's padding. `hold`
is then learned separately and added on top. Where a cell has evidence the
learned ratio absorbs this; where it does not, the blend falls back toward ratio
1.0, which is the prior itself, dwell included. Most of the network is in that
state most of the time.

**What to do.** Ship `no-prior`, or keep the prior only as a shape (normalise it
so its length-weighted mean matches the learned global pace) rather than as a
level.

## 2. `sections` is competitive with no corridor pooling at all

Not a subtlety - a section-level model has *nothing* to back off to but one
city-wide number, and it still beat `full` by 5%.

The cell layer really does carry more signal. Of the total length-weighted
variance of log pace, 0.3751, the between-cell component is 0.2226 (59%) and
the between-section component 0.1383 (37%). Cells win on paper.

They lose in practice on how often that signal is refreshed. Over 18.6 hours a
cell is crossed 11.5 times and a section 64.5 times. At any single prediction
instant the cell-level fast term has a mean effective weight of 0.41 against
K_CELL = 4.0, so it supplies 8.3% of the blend; the section-level fast term is
no better in weight but each observation stands for five times as much road.

So the finer unit is a better description of the city that the data cannot keep
current. Combined with finding 1, `sections` mostly wins by not paying the
prior's bias - the obvious next experiment is `sections` *and* `no-prior`
together, which no variant currently tests.

## 3. The fast half-life earns almost nothing

Same measurement, read the other way. At prediction time the four pace layers
contribute these mean shares of the blend:

| layer | frac of units with any weight | mean effective weight | share of blend |
|---|---|---|---|
| cell, fast (480 s) | 62.6% | 0.41 | 8.3% |
| cell, slow (5400 s) | 69.0% | 2.62 | 30.1% |
| corridor, fast | 81.5% | 1.89 | 22.7% |
| corridor, slow | 86.4% | 12.14 | 51.8% |

A cell sees 11.5 crossings in 18.6 hours, which is 0.4 crossings per 480-second
half-life. The cell-fast term is diluted almost to nothing by K_CELL = 4.0
before it is ever read. Turning `fast` off costs 2% because three quarters of
what it was contributing was the corridor-fast term, and that one survives.

If live traffic response matters, the fast term needs a smaller K at the
corridor level or a longer half-life at the cell level - not both terms at the
same shrinkage.

## 4. `vehicle-offset` inverts with horizon because the offset does not last

Best of ours at 0-1 min (24 s vs `full`'s 29), worst at 20-45 min (408 s vs
319). The cause is that `_factor` multiplies the *entire* remaining ETA by a
ratio measured from the last few minutes.

Autocorrelation of a vehicle's own speed ratio, in 5-minute windows, over 13 847
window pairs:

| lag | 0 | 5 min | 10 min | 20 min | 40 min | 80 min |
|---|---|---|---|---|---|---|
| corr | 1.000 | 0.331 | 0.171 | 0.046 | 0.066 | 0.064 |

The offset is real for about 5 minutes and gone by 20 - an e-folding time near
4.5 minutes. Applied undiminished to a 45-minute ETA, a vehicle running 30% slow
gets 12 extra minutes it will not spend.

**What to do.** Decay the factor toward 1.0 along the path rather than applying
it flat: weight it by roughly `exp(-h / 300)` for a lead time `h` in seconds, so
the next stop gets the full correction and the far end of the trip gets none.
That should keep the 0-2 min gain and delete the 10-45 min loss.

## 5. `schedule-offset` beats the operator's own API because of a tail

Both use the same method - `diag` established that `trip_updates` carries the
vehicle's current lateness forward unchanged - so the 166 s vs 224 s gap is
about the *input*, not the method. But it is not that the API is uniformly
worse. At the 0-1 minute horizon, one minute before the bus actually arrived:

| predictor | median AE | MAE | RMSE | within 120 s |
|---|---|---|---|---|
| `full` | 14 s | 29 | 54 | 96% |
| `schedule-offset` | 17 s | 33 | 60 | 95% |
| `api` | 40 s | 130 | 304 | 81% |
| `lad` | 39 s | 96 | 190 | 82% |

The API's typical answer is fine - 40 seconds out, one minute before arrival.
Its mean is wrecked by the 19% of answers that are more than two minutes wrong
at that range, when nothing but a wrong vehicle position can be responsible.
Its bias there is -31 s and the board's is -73 s: the tail predicts arrival
*earlier* than it happened, which is what a stale position or a bus that has
already been reassigned off the trip looks like.

The feed is not stale in the ordinary sense - `pred` revises every 15-30 s,
and only 0.3% of revisions leave the value unchanged. Whatever produces the
tail survives being refreshed twice a minute.

## The shape of all five

Three distinct mechanisms account for the lot.

1. **A prior is only worth its bias.** Findings 1 and 2. The timetable is used
   as a level and its level is wrong by 6%, so every cell without live evidence
   inherits that error. Shrinkage does not rescue a biased target; it delivers
   it.
2. **Resolution is worthless faster than it is refreshed.** Findings 2 and 3.
   Cells and short half-lives both describe the city more finely than 11.5
   crossings per cell per day can support, and a fixed shrinkage constant then
   throws most of that description away.
3. **A correction is only valid over the time it persists.** Findings 4 and 5.
   A vehicle's offset lasts 5 minutes and is applied over 45; the operator's
   position error lasts as long as its position is wrong and is applied to
   everything downstream of it.

The one thing to take away: every one of these is a mismatch between how long a
piece of evidence is good for and how far it is being carried.
