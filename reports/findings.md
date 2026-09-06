# Why the approaches scored what they did

`approaches.md` says which variants won. It does not say why, and five of the
results contradicted a claim the model makes about itself. A sixth finding, on
what the nightly shutdown does to the model, came out of asking whether such a
sparse subset can be trusted. Each one below was measured on the same recording
of `data/feed.db` - 245 307 cell crossings over 19 228 distinct cells - not
argued from the code.

The scripts behind these numbers were one-off instrumentation of `replay.run`,
not checked in. What is checked in is the conclusion and the number that
supports it.

**What the recording covers.** The replay spans 18.6 hours, but that is not
18.6 hours of service. The fixes fall in two windows - 2026-09-05 20:00-23:59
and 2026-09-06 00:00-09:32 - and the second is mostly the overnight shutdown,
when there is no public transport in Lviv because of the war. Hours 01:00-04:59
returned zero vehicles on all 2880 polls. So the evidence is roughly 8.5 hours
of moving traffic: an evening peak and a morning peak, with **no data at all
for 10:00-19:00**. Statements about what the *prior* contains hold for all 24
slots, since they read the prior array itself. Statements about what the *city*
does are verified over hours 05-09 and 20-23 only.

None of the numbers below carry a confidence interval - unlike
`approaches.md`, which resamples over whole trips and reports 95% intervals,
this is a single recording measured once. Treat every finding here as
provisional: a plausible read of two short windows on one weekend, not a result
confirmed across recordings.

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

## 6. The nightly shutdown resets the model onto the prior every morning

There is no service in Lviv between roughly 00:00 and 05:30. Every weight is
stamped with the time it was earned and decays from that stamp, so a 6.5-hour
gap is 4.3 slow half-lives and about 5% of the weight survives it. Snapshotting
the model each hour across the night:

| local | `full` believes | `no-prior` believes | cell-slow w | corr-slow w |
|---|---|---|---|---|
| 22:00 | 19.0 km/h | 19.6 | 1.40 | 6.48 |
| 23:00 | 18.6 | 19.4 | 1.13 | 5.22 |
| 02:00 | 17.7 | 19.1 | 0.29 | 1.35 |
| 05:00 | 17.2 | 19.1 | 0.07 | 0.34 |
| 06:00 | 18.0 | 19.6 | 0.05 | 0.25 |
| 07:00 | 19.4 | 20.0 | 0.51 | 2.38 |
| 08:00 | 20.1 | 20.7 | 1.70 | 7.86 |

Against K_CELL = K_CORR = 4.0, a cell-slow weight of 0.05 is 1.2% of the blend:
at 06:00 the model is essentially all prior and global, and does not recover
until 08:00. Measured speed in hours 05-09 is 20.3-23.1 km/h, so `full` opens
the morning peak believing the city is 15% slower than it is.

`no-prior` drifts only 19.4 to 19.1 over the same night, because what it falls
back to is the learned global mean rather than the timetable. Finding 1's bias
is therefore not a steady-state cost that a long run amortises - it is
re-inflicted at the start of every service day.

Saving a snapshot does not help. `state.py` argues that age needs no check
because a stale snapshot fades back to the timetable prior on its own; that is
exactly the failure here, not the safeguard. The fix is a fallback that
survives the gap: an hour-of-day by day-of-week profile learned across days, or
a third EWMA with a half-life measured in days beneath the existing two.

The collector itself is untouched by the shutdown - 2880 consecutive polls
returning zero vehicles, no errors, and the frequent short empty replies during
the day (8.6% of polls at 08:00) never run longer than 3 polls, well under
STALE = 120 s.

## The shape of all six

Three distinct mechanisms account for the lot.

1. **A prior is only worth its bias.** Findings 1, 2 and 6. The timetable is
   used as a level and its level is wrong by 6%, so every cell without live
   evidence inherits that error. Shrinkage does not rescue a biased target; it
   delivers it - and the nightly shutdown puts the whole network back into that
   state once a day.
2. **Resolution is worthless faster than it is refreshed.** Findings 2 and 3.
   Cells and short half-lives both describe the city more finely than 11.5
   crossings per cell per recording can support, and a fixed shrinkage
   constant then throws most of that description away.
3. **A correction is only valid over the time it persists.** Findings 4, 5 and
   6. A vehicle's offset lasts 5 minutes and is applied over 45; the operator's
   position error lasts as long as its position is wrong and is applied to
   everything downstream of it; and the road model's own memory lasts 90
   minutes, which is shorter than the night it has to be carried across.

The one thing to take away: every one of these is a mismatch between how long a
piece of evidence is good for and how far it is being carried.
