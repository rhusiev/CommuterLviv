# Why the approaches scored what they did

`approaches.md` says which variants won. It does not say why, and five of the
results contradicted a claim the model makes about itself. A sixth finding, on
what the nightly shutdown does to the model, came out of asking whether such a
sparse subset can be trusted. The seventh is of a different kind: two defects in
how the predictors were being paired, which invalidated the scores that led to
the other six being investigated at all. The eighth collapses three of the
others into one, and is the only one that says what to change. Each one below
was measured on the same
recording of `data/feed.db` - 245 307 cell crossings over 19 228 distinct
cells - not argued from the code.

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

## 1. The timetable prior costs 4% MAE, and the reasons given for it do not hold

The headline was 12% before finding 7's scoring defects were fixed; on the
corrected run it is `no-prior` 114 s against `full` 119 s. The direction did not
change and none of the mechanism below did - every measurement in this section
is taken off the replay itself, not off the scoring - but the size did, and 4%
is small enough that it is the argument and not the margin that decides this.


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
ETA. That shows up as bias only at the short horizons, where `full` runs +6 s at
0-1 min and +10 s at 1-2 min against `no-prior`'s +2 s: pooled over all horizons
it is cancelled by the long buckets, where every variant runs negative. The
mechanism is a double count.
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
city-wide number, and it lands within 2% of `full` anyway: 121 s against 119 s.
(Before finding 7's fixes it appeared to beat `full` by 5%. It does not; it
ties.)

The cell layer really does carry more signal. Of the total length-weighted
variance of log pace, 0.3751, the between-cell component is 0.2226 (59%) and
the between-section component 0.1383 (37%). Cells win on paper.

They lose in practice on how often that signal is refreshed. Over 18.6 hours a
cell is crossed 11.5 times and a section 64.5 times. At any single prediction
instant the cell-level fast term has a mean effective weight of 0.41 against
K_CELL = 4.0, so it supplies 8.3% of the blend; the section-level fast term is
no better in weight but each observation stands for five times as much road.

So the finer unit is a better description of the city that the data cannot keep
current.

The obvious next experiment - `sections` *and* `no-prior` together - has since
been run as `sections-no-prior`, and it does not work: 127 s, worse than either
of its parents and 6% worse than `full`. Dropping the prior helps a cell-level
model, which has a corridor to fall back on; it hurts a section-level one, which
has only the global mean. The two changes are not additive because they both
spend the same thing, which is what the model falls back to where it has no
evidence.

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

Tied for best of ours at 0-1 min (15 s, with `no-prior`, against `full`'s 17)
and worst of ours by a wide margin at 20-45 min (325 s against 212). The cause
is that `_factor` multiplies the *entire* remaining ETA by a ratio measured from
the last few minutes.

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

That was done, as `offset-decay`, and it behaves exactly as predicted: 16 s at
0-1 min and 27 s at 1-2 min, keeping most of `vehicle-offset`'s short-horizon
edge over `full` (17 and 29), while 20-45 min falls from 325 s to 219 s, level
with `full`'s 212. Overall it is 121 s against `full`'s 119. So the diagnosis
was right and the fix works, and it still does not buy anything: what the
vehicle's own recent speed knows about the next two minutes, the corridor's
fast term already knows too.

## 5. The timetable with a lateness offset beats the operator's own API, because of a tail

Numbers below are from the first full run with finding 7's three scoring
defects fixed: 80572 crossings over 1056 minutes, 1318685 predictions every
approach answered.

`schedule-offset` scores 208 s and `api` 467 s, and `diag` established that both
carry the vehicle's current lateness forward unchanged. Same method, so the gap
is about the *input*. But the API is not uniformly worse. At the 0-1 minute
horizon, one minute before the bus actually arrived:

| predictor | median AE | MAE | RMSE | bias | within 120 s |
|---|---|---|---|---|---|
| `full` | 11 s | 17 | 31 | +6 | 98.9% |
| `schedule-offset` | 16 s | 27 | 46 | +13 | 97.7% |
| `api` | 39 s | 297 | 1140 | -112 | 79.1% |

The API's typical answer is fine - 39 seconds out, one minute before arrival,
which is within a bus length of right. Its mean is wrecked by the 21% of
answers that are more than two minutes wrong at that range, when nothing but a
wrong vehicle position can be responsible. Its bias there is -112 s: the tail
predicts arrival *earlier* than it happened, which is what a stale position or
a bus already reassigned off the trip looks like. The tail does not thin out
with horizon either - `api` sits between 297 and 607 s across all six buckets
while everything else grows from 17 to 212, so at 20-45 minutes it is only
twice as bad as at one minute. That is the signature of a constant fraction of
answers being wrong about *which bus*, not of a forecast losing accuracy.

The feed is not stale in the ordinary sense - `pred` revises every 15-30 s, and
only 0.3% of revisions leave the value unchanged. Whatever produces the tail
survives being refreshed twice a minute.

The public arrivals board is a different story, and finding 7 is what made it
readable: scored fresh on the 161466 predictions it also answered, `lad` is
111 s against `api`'s 408 s on those same events. Both are the operator's.
Whatever produces the board is doing substantially more than replaying
`trip_updates`, and it is the harder of the two to beat - `full` scores 85 s
there, a 24% margin rather than a fourfold one.

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

## 7. Three defects in the scoring, all in how an answer is matched to a crossing

This one is not about the model. It is about the measurement, and it invalidates
every number written before 2026-09-06 in `approaches.md` and `sweeps.json`.

A crossing is one event, and the predictors do not agree on how to name one.
Ours knows the vehicle, the trip, which pass of that trip it is on, and the
stop. `trip_updates` names a trip and a stop. The arrivals board names a vehicle
and a stop, and never says which trip or which pass. `truth.py` handled that by
keeping only the crossings that *both* namings picked out uniquely, and
`score.py` intersected all four predictors' answers into one common support.
Both decisions let the weakest namer set the terms for everyone.

**The common support.** The board answers about only the 40 stops the collector
polls. With it inside the intersection, the headline table scored every approach
on 23 929 of about 199 000 predictions - 12% - and all of them near those 40
stops. Which stops the collector happens to poll was deciding every published
comparison.

**The ground truth.** Uniqueness was checked on `(trip, stop)` and on
`(vehicle, stop)`, neither of which includes the pass. Over 90 minutes a vehicle
rarely revisits a stop and almost everything survived. Over a six-hour window it
passes each of its stops several times. Measured on one window of 48 418
crossings:

| naming | crossings it names uniquely |
|---|---|
| `(trip, stop)` | 45 645 (94.3%) |
| `(vehicle, stop)` | 5 277 (10.9%) |

So 89% of the ground truth was being discarded to accommodate the one predictor
that answers about 40 stops. The kept fraction fell with window length - 80%
over 2.75 hours, 11.5% over 6 - which is what first made it visible: identical
configs returned fewer and fewer scored predictions as the recording grew.

The second half of that defect is worse than the deletion. Our own predictions
were addressed by `(trip, stop)` as well, so a prediction about one pass could
be scored against a *different* pass of the same trip. On a window whose warmup
outlasted the data, every single one of 1.6 M predictions was matched that way -
zero of them to the pass they were actually about.

Both are fixed. `Truth` keeps every crossing, keyed in full by
`(vehicle, trip, pass, stop)`, and `predictors.ours` uses that full key.
`score.paired` excludes the board from the main support by name and scores it on
its own.

Uniqueness turned out to be the wrong repair for the partial namings. What
settles which pass a predictor meant is *when it spoke*: a board saying "arrives
in 4 minutes" at 20:31 means the next crossing at or after 20:31. Each partial
naming is now a time-ordered `Truth.Index` asked with a key and an instant, which
uses only the time the predictor spoke and never the value it gave, so it cannot
be tuned to flatter anybody. Every crossing becomes addressable by every naming:
`schedule` went from 94% coverage to 100%, `api` to 95%, and the board from 1.7%
to 17.8%.

**The standing value.** `_from_log` held a published value valid until the feed
replaced it. That is right for `trip_updates`, which the collector records as a
change log with a 5 s deadband. It is wrong for the arrivals board, which is
recorded as a *snapshot* of what the board displayed at each 60 s poll: a
vehicle missing from the next poll is a board that has stopped answering, not
one repeating itself. So a value published at 21:00 was still being scored at
07:00 the next morning. It cost the board an MAE of 4451 s against a median
absolute error of 96 s - about 11% of its scored epochs were reading a value
hours old. `_from_log` now takes a staleness bound, unset for the change log and
120 s - two poll periods - for the board.

That third fix changes the answer to a question the report had already
published. On 2026-09-06 07:00-09:00 the board scores 37 s MAE one minute ahead
and 101 s five to ten minutes ahead, against `api`'s 147 s and 257 s on the same
window; over the full corrected run it is 111 s against `api`'s 408 s on the
161466 events both answered. The public board is not a worse `trip_updates`; it
is several times better than it, and the closest thing to a real competitor this
comparison has - `full` scores 85 s on those same events, a 24% margin. Finding
5's table was reading the board's stale-value tail, not the board.

## 8. Findings 1, 2 and 3 are one finding, and tuning collects all of it

Three of the findings above are separate observations about the same knob.
Finding 1 says the timetable prior costs 4% because its level is wrong; finding
2 says a coarser unit does about as well as the fine one; finding 3 says the
fast half-life is far too short. Each was measured by deleting a piece of the
model. Setting the four shrinkage and half-life constants instead - `k_unit`
4 to 1, `k_corr` 4 to 0.5, `fast_hl` 480 s to 7200, `slow_hl` 5400 s to 43200,
the `tuned` variant - collects the whole of it and more:

| bucket | `full` | `tuned` | `tuned-no-prior` | `no-prior` |
|---|---|---|---|---|
| 0-1 min | 18 | 15 | 15 | 16 |
| 1-2 min | 30 | 25 | 24 | 25 |
| 2-5 min | 49 | 40 | 39 | 41 |
| 5-10 min | 80 | 67 | 65 | 69 |
| 10-20 min | 130 | 115 | 113 | 117 |
| 20-45 min | 224 | 234 | 239 | 230 |

MAE in seconds, all four scored on one common support of 94 376 crossings
(`check_prior.py`).

Read the middle two columns together. Deleting the timetable prior costs `full`
2 s at 0-1 min and 13 s at 10-20; it costs `tuned` 0 s and 2 s. **Once the
shrinkage is loosened the prior is nearly inert.** That is the mechanism behind
finding 1: the prior was never harmful in itself, it was harmful because
`k_unit = 4` kept pulling cells back onto it long after those cells had enough
live evidence of their own. Delete the prior or stop shrinking towards it - the
model ends up in the same place, and `no-prior` was measuring the shrinkage
constant all along.

The last row is the price and it is a real one. `tuned` runs a bias of -66 s
against `full`'s -10, and loses the 20-45 minute bucket by 10 s. Trusting live
evidence sooner and forgetting it later means the model tracks the road as it is
now and carries that state 45 minutes ahead, which is free at three minutes and
wrong at thirty. This is mechanism 3 below, arrived at from the opposite
direction: the same mismatch between how long evidence is good for and how far
it is carried, only now it is *our* evidence being over-carried rather than the
vehicle offset or the operator's position.

**What to do.** Nothing yet, and this is the important part. Four constants
tuned on one day's recording are fitted to that day, and the direction they all
moved - less shrinkage, longer memory, a half-life longer than the recording
itself - is exactly what a recording too short to contain any real within-day
variation would produce. Whether Lviv genuinely has little within-day variation
or the recording is simply too short to show it cannot be told apart here. That
is the first thing to re-run once the recording spans three weekdays.

## The shape of the seven model findings

Finding 7 stands apart - it is a defect in the measuring, not a property of the
city or the model. Three distinct mechanisms account for the other seven.

1. **A prior is only worth its bias.** Findings 1, 2, 6 and 8. The timetable is
   used as a level and its level is wrong by 6%, so every cell without live
   evidence inherits that error. Shrinkage does not rescue a biased target; it
   delivers it - and the nightly shutdown puts the whole network back into that
   state once a day. Finding 8 sharpens this: the harm is in the shrinkage, not
   in the prior, and loosening the one makes the other stop mattering.
2. **Resolution is worthless faster than it is refreshed.** Findings 2, 3 and 8.
   Cells and short half-lives both describe the city more finely than 11.5
   crossings per cell per recording can support, and a fixed shrinkage
   constant then throws most of that description away.
3. **A correction is only valid over the time it persists.** Findings 4, 5, 6
   and 8. A vehicle's offset lasts 5 minutes and is applied over 45; the
   operator's position error lasts as long as its position is wrong and is
   applied to everything downstream of it; the road model's own memory lasts 90
   minutes, which is shorter than the night it has to be carried across; and a
   tuned model that remembers for twelve hours carries the current state of the
   road 45 minutes ahead of itself, which is where its only loss is.

The one thing to take away: every one of these is a mismatch between how long a
piece of evidence is good for and how far it is being carried.
