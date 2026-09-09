# Why the approaches scored what they did

`approaches.md` says which variants won. It does not say why, and five of the
results contradicted a claim the model makes about itself. A sixth finding, on
what the nightly shutdown does to the model, came out of asking whether such a
sparse subset can be trusted. The seventh is of a different kind: two defects in
how the predictors were being paired, which invalidated the scores that led to
the other six being investigated at all. The eighth collapses three of the
others into one, and is the only one that says what to change. The ninth is the
first offline-fitted model in the project and says what one is worth. Findings 1
to 8 were each measured on the same recording of `data/feed.db` - 245 307 cell
crossings over 19 228 distinct cells - not argued from the code; finding 9 is
measured on the longer recording described below.

The scripts behind these numbers were one-off instrumentation of `replay.run`,
not checked in. What is checked in is the conclusion and the number that
supports it.

**What the recording covers.** Findings 1 to 8 were measured while the replay
spanned 18.6 hours, of which only 8.5 carried moving traffic: 2026-09-05
20:00-23:59 and 2026-09-06 00:00-09:32, the second mostly the overnight
shutdown, when there is no public transport in Lviv because of the war. Hours
01:00-04:59 returned zero vehicles on all 2880 polls, and there was **no data at
all for 10:00-19:00**, which is the gap finding 9's recording fills: it runs to
2026-09-06 18:56 and adds the middle of a weekday, though still only the one
day. Statements about what the *prior* contains hold for all 24
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
a third EWMA with a half-life measured in days beneath the existing two. The
second was built and is finding 11; it is worth 18% of the morning's MAE.

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

## 9. An offline model of the residual is worth 10%, under one loss and only where it was fitted

Phase 4 corrects the shipped model instead of replacing it: one row per emitted
prediction, fourteen columns all readable at the instant the prediction was
made, and the target is `log(actual / predicted)` so a correction multiplies an
ETA rather than adding seconds to it. The whole recording gives 3 010 244 rows
over 130 426 crossings. Five models were fitted on it, and the split - which
rows are training and which are test - changed the answer more than the choice
of model did.

The plan's split fits on the evening and scores on everything after 05:30. On
it **every model is worse than doing nothing**, from `resid-linear` at +16.6 s
[+14.8, +18.3] to `resid-gbm` at +38.8 s, against `full`'s 168.4 s
(`reports/residual.md`). Splitting the same rows at midday instead - fit on
everything emitted before 12:00, score on 12:00 to 18:56, still one forward
replay and still strictly causal - reverses it: `resid-quantile` scores 145.5 s
against `full`'s 161.2, a **9.8% gain, interval [-20.1, -11.6] s**
(`reports/residual-midday.md`).

Both splits are honest and they disagree, so the disagreement is the finding.
Three hours of evening traffic, 141 559 rows, do not describe the day: the
evening-fitted correction still *helps* at short horizons - `resid-linear` beats
`full` at 1-2, 2-5 and 5-10 minutes, 70 s against 76 at 5-10 - and then loses
44 s in the 20-45 minute bucket, 252 against 208, which is where the pooled
number comes from. A correction learned in one traffic regime is applied in
another, and the further ahead it reaches the more of the wrong regime it
carries.

The loss function matters as much as the model class. On the midday split the
same trees under squared loss score 154.6 s, an interval of [-13.2, +0.4] that
does not separate from zero; under quantile loss at 0.5 they score 145.5. The
residual is right-skewed - a bus can be arbitrarily late and only slightly early
- so its mean and its median are different numbers, and MAE is minimised by the
median. Fitting the mean of a skewed residual and then scoring the result by MAE
is fitting one quantity and grading another. The same skew sank the `median`
baseline in Phase 3, where a sum of medians of right-skewed cell times runs
short; correcting a whole ETA by one median ratio is where it finally pays.

Capacity, by contrast, buys almost nothing. Ordering the midday split by what
each model can express - constant +2.0 s, linear -1.5, trees -6.6, trees under
the right loss -15.8, a two-layer network +39.2 - the only large step is the
loss. The network is not broken: in-sample it cuts training MAE from 135 s to
80 s and its output correlates 0.67 with the target. It is overfitting 141 559
evening rows and then extrapolating, which is what a flexible model does when
asked about a region it never saw.

Blanking each feature group and refitting the winner says what carries it:

| dropped | MAE s | cost s |
|---|---|---|
| nothing | 145.5 | - |
| the model's own evidence weights | 165.4 | +20.0 |
| the vehicle's speed ratio and fix ages | 153.6 | +8.1 |
| the timetable's own answer and lateness | 152.4 | +6.9 |
| hour of day and route | 150.9 | +5.5 |
| horizon, distance and stops ahead | 150.0 | +4.5 |

**How much the model knew is worth more than anything it knew.** The three
evidence weights - how much live traffic data the ETA's path actually rested on
- carry twice what any other group does, and more than the horizon itself. The
correction is not learning about the city; it is learning when the physical
model was guessing.

**What to do.** Nothing ships. A residual model fitted on one day's morning and
applied to that day's afternoon is the most in-sample thing in this project, and
the evening split is there to show how fast the gain evaporates when the
training window stops resembling the test one. What Phase 6 has to answer is
whether a model fitted on *previous days* transfers at all; if it does not, the
9.8% is a measurement of one afternoon and not a component.

## 10. Blending the predictors is the largest win in the project, and only the robust fit survives the night

Phase 5 fits, per horizon bucket, a weighted average of what four predictors
said about the same crossing at the same instant: `full`, `no-prior`,
`sections` and the operator's `api`. The weights are made to sum to one by
construction, so a blend is always an average and never a rescaling, and each
bucket carries an intercept. Three rules are scored - weights fitted under
squared loss (`stack`), the same weights fitted under absolute loss
(`stack-robust`), and the member-wise median, which fits nothing
(`stack-median`) - plus a control, `debias`, which is `full` alone with only
the intercept fitted.

On the midday split every rule wins and the ordering is small:
**`stack-robust` 95.2 s against `full`'s 109.7, -14.4 s [-15.7, -13.2],
13.2%**, `stack` 97.2 s, `stack-median` 107.0 s
(`reports/stack-midday.md`). On the plan's split - fitted on three evening
hours, scored on the whole next day - the ordering is not small at all:
**`stack-robust` still wins, 107.6 s against 116.7, -9.0 s [-10.3, -7.6], but
`stack` collapses to +0.8 s [-2.1, +3.7], which does not separate from zero**
(`reports/stack.md`). The fit-free median keeps -5.4 s [-6.3, -4.6]. The same
weights, the same rows, the same members: the only difference is whether the
fit is allowed to chase the far tail of the evening's errors, and chasing it is
what stops the weights transferring across the night.

**None of it is de-biasing.** The intercepts the blends fit are large - up to
+122 s in the 20-45 minute bucket - so the control is what makes the rest
readable. Fitting only the intercept is worth +0.3 s [+0.2, +0.5] on the midday
split and **+9.5 s [+8.6, +10.4] on the plan's**, where it actively hurts: it
learns that `full` runs late in the evening (intercepts -5 s at 0-1 min falling
to -84 s at 20-45) and then applies that correction to a morning where `full`
runs early. The bias does not survive the night, which is finding 6's nightly
reset seen from the other side. The blend's win is mixing, not levelling.

**The uncorrelated member is worthless.** `api` errors correlate 0.03 to 0.11
with everyone else's, which is exactly the diversity a stack is supposed to
exploit, and every fitted weight it gets is between -0.01 and +0.09. A blend
needs members that are both different and *good*; `api` at 575-679 s MAE is
different and bad, and the fit prices it at zero. What the weights actually buy
is a horizon-dependent trade among the three of our own variants: `no-prior`
carries the short buckets (+1.37 at 0-1 min on the midday split, against
`full`'s -0.33), `sections` takes over as the horizon lengthens (+0.49 at
20-45), and `full` holds a small negative weight throughout - it is being used
to subtract the prior's pull out of the others, not to predict.

**A fifth member does not help, and across a night it hurts.** `tuned` is the
best single variant this project has, and it is also the most correlated with
`full`, so adding it to the four tests whether the blend wants quality or
diversity. On the midday split it buys 0.9 s (`stack-robust` 93.9 against 95.2 -
`reports/stack-tuned-midday.md`). On the plan's split every rule gets worse,
by 6 to 15 s: `stack` 123.3 against 116.7 for `full`, `stack-robust` 122.4,
`stack-median` 109.3 against its own 107.6 (`reports/stack-tuned.md`). A fifth
correlated member gives the fit one more way to overfit the evening, and that is
all it gives. `stack.MEMBERS` keeps the four.

**What to do.** `stack-robust` is the first thing in this project worth
shipping as a change to what users would see: it beats every member on both
splits, its weights are six vectors of four numbers, and it needs no model the
project does not already run. The cost is running three variants instead of
one, which is three times the replay work for 8-13% MAE. Before that, Phase 6
has to say whether weights fitted on previous days transfer - the same question
finding 9 leaves open, and the plan's split is the reason to ask it: a rule
fitted at 11:59 and used at 12:00 is not how a deployment works.

## 11. A third half-life measured in days repairs the morning, and costs nothing to add

Finding 6 named two possible fixes for the nightly reset. This is the cheaper
one: a third EWMA beneath the existing two at both scales, `day_hl = 86400 s`,
shipped as the `slow-day` variant. Nothing else changes - the same blend, the
same shrinkage constants, one more term in each of the two back-off levels.

Scored where the reset does its damage - the model warmed on the whole previous
evening and night, then scored on the morning up to 09:00 (`--warmup 33000
--to 2026-09-06T09:00`, 34 469 crossings, 380 317 common predictions):

| | MAE s | 0-1 | 1-2 | 2-5 | 5-10 | 10-20 | 20-45 | bias |
|---|---|---|---|---|---|---|---|---|
| `slow-day` | 109 | 16 | 28 | 45 | 75 | 122 | 199 | +18 |
| `no-prior` | 110 | 15 | 26 | 43 | 73 | 123 | 210 | -26 |
| `full` | 134 | 19 | 33 | 55 | 93 | 153 | 240 | +47 |
| `api` | 279 | | | | | | | |
| `schedule` | 758 | | | | | | | |

**`slow-day` beats `full` at every horizon, by 18% overall.** That is the size
of finding 6's damage, now measured directly rather than inferred from the
weights. It also beats `no-prior` at the two long buckets (122 against 123, 199
against 210) while `no-prior` keeps the short ones, which is the expected shape:
what yesterday's cells carry is the level of the road, and the level matters
more the further ahead you look.

**Over a whole day the win shrinks to what a whole day dilutes it to.** Scored
across the full recording against the same three (`reports/slow-day.md`, 129 684
crossings, 2 537 566 common predictions): `no-prior` 112, `slow-day` 113,
`tuned` 113, `full` 118. The three are tied and 4-5% ahead of `full`, and
`slow-day` is better than `full` at every horizon out to 20 minutes (16/25/40/
66/111 against 18/29/47/76/123) and worse at 20-45 (209 against 203). The
morning is a few hours of one recording; measured against all of it, the
overnight repair is 5 s of the 25 it is worth at 08:00. What distinguishes
`slow-day` from the other two is the bias it does *not* have: -51 s against
`no-prior`'s -58 and `tuned`'s -68, with the same MAE.

The two fixes are not equivalent. `no-prior` repairs the morning by never
believing the timetable at all, and pays for it with a -26 s bias it carries all
day. `slow-day` keeps the prior and simply stops being alone with it at 06:00;
its bias is +18 s, between the two. `day_hl` defaults to 0, so the third term is
absent unless a variant asks for it and `full` is unchanged.

## 12. The 80% interval is worth having, and the fitted one is the worse of the two

Finding 9 left the interval open; Phase 4 now produces one. Two rules make the
0.1 and 0.9 edges of a band around `full`'s prediction: `band-const`, a weighted
empirical quantile of the residual per horizon bucket, which fits nothing beyond
twelve numbers, and `band-quantile`, two quantile-loss tree fits on the same
features the point models use. Scored by empirical coverage against the 80%
target, by mean width, and by the check loss at each edge:

| split | rule | covers | width s | pinball 0.1 / 0.9 |
|---|---|---|---|---|
| plan's | `band-const` | 76.1% | 399 | 37.0 / 83.6 |
| plan's | `band-quantile` | 59.3% | 300 | 34.1 / 95.0 |
| midday | `band-const` | 82.2% | 403 | 31.0 / 74.2 |
| midday | `band-quantile` | 67.2% | 279 | 29.8 / 53.1 |

**Both bands are too narrow, and the fitted one is much too narrow.** On the
midday split - where the fit and the test share a regime, and where
`resid-quantile` is the best point model there is at 145.5 s - the fitted band
still loses 15 points of coverage to the twelve-number one while being 31%
narrower. Across the night both lose another 6 to 8 points, which is the same
transfer failure findings 9 and 10 measure, but it is not the main effect here.

The mechanism is under-dispersion, and the horizon table shows it. Coverage and
mean width by horizon, on the plan's split:

| band | 0-1 | 1-2 | 2-5 | 5-10 | 10-20 | 20-45 |
|---|---|---|---|---|---|---|
| `band-const` | 72% / 93 s | 87% / 111 s | 87% / 164 s | 86% / 251 s | 82% / 392 s | 67% / 619 s |
| `band-quantile` | 70% / 46 s | 81% / 89 s | 78% / 143 s | 72% / 216 s | 63% / 306 s | 43% / 430 s |

**The fitted band is narrower than the empirical one at every horizon, and the
deficit widens with the horizon** - half the width at one minute, two thirds of
it at 45. That is what a regularised conditional quantile does when the features
cannot resolve the tail: it pulls both edges toward the conditional median, and
the tail is where an interval lives. What the features carry beyond the horizon
is worth 20 s of MAE on a point estimate (finding 9's ablation: the model's own
evidence weights are the largest group) and evidently nothing on a quantile, so
the fit is paying shrinkage for information it cannot use here. `band-const` is
the horizon lookup, done exactly, and it wins by not shrinking.

The 0-1 minute bucket is the one place both undercover, 72% and 70%. A
multiplicative correction cannot make a band wider than a fraction of a
93-second ETA, and at that horizon the residual has an additive floor - the
truth itself is interpolated between fixes. Nothing here fixes that; a band at
one minute should carry a constant term in seconds.

**What to ship.** `band-const`: on the split that resembles a deployment it is
within 4 points of its target, and it is twelve numbers recomputed per day. A
fitted band is worth revisiting only per bucket - one quantile fit inside each
horizon bucket, so the shrinkage happens around a level that is already right -
and with an additive term at the short horizons.

## 13. The three geometry constants are worth 2 seconds between them, and the pooling cell is the only one shipped wrong

The three numbers that decide the shape of the model's map were swept last,
because they were expected to cost a network rebuild. They do not - only `Shape`
depends on them, so `regrid` re-cells an already-built network and each point
replays in 187-230 s. All three were swept on `full`, paired on a common support
of 129 684 crossings over 1360 epochs.

`cell` is the length of one speed-field cell along a shape, in metres. The
shipped 100 m is already the best value, and the whole range is worth 2.1 s.

```
  cell=50            167.8    bias -53.2    [+1.0, +1.7]   separated
  cell=100           166.5    bias -53.9    [+0.0, +0.0]   <- best
  cell=200           167.1    bias -59.0    [+0.2, +1.2]   separated
  cell=400           168.6    bias -70.9    [+1.3, +3.0]   separated
```

It is a shallow U. At 50 m the same crossings are split across twice as many
cells and each one is estimated from half the evidence; at 400 m one cell spans
road that is genuinely two different roads, and the bias goes with it, from -54
to -71 s. Nothing here is worth changing.

`grid` is the size of the shared spatial cell that pools different routes into
one corridor. The shipped 120 m is the second worst of the five values tried.

```
  grid=30            164.4    bias -62.6    [+0.0, +0.0]   <- best
  grid=45            164.7    bias -58.9    [-0.0, +0.6]   not separated
  grid=60            165.0    bias -57.4    [+0.1, +1.0]   separated
  grid=120           166.7    bias -53.6    [+1.6, +2.9]   separated
  grid=250           167.4    bias -53.1          (first sweep)
```

This one is monotone: the smaller the pooling cell, the better, down to the
30 m the sweep was extended to reach. A 30 m cell is narrower than a road, so
at that point two routes only share a corridor where they genuinely run on the
same asphalt. That is finding 2 read from the other side - `sections`, which
pools nothing across routes, is already competitive with the corridor layer, so
shrinking the corridor toward no pooling should help, and it does. It helps by
2.3 s, or 1.4%.

`octants` is how many heading classes a corridor cell is split into.

```
  octants=4          167.7    bias -51.1    [+0.8, +1.2]   separated
  octants=8          166.9    bias -53.7    [-0.0, +0.3]   not separated
  octants=16         166.7    bias -55.2    [+0.0, +0.0]   <- best
```

Four classes are 90 degrees wide, which is wide enough to put a road and its
cross street in one bucket, and that costs 1.0 s. Eight and sixteen are not
separated. The direction a vehicle is travelling matters, and 45 degrees is
enough to say it.

**What to ship.** `cell=100` and `octants=8` stay. `grid` should come down to
45 m - 30 is nominally best but is not separated from 45, and 45 keeps more
evidence per cell for the days when there is less of it. The change has been
measured on `full` only; before `network.DEFAULT` is changed it wants one
confirmation on `stack-robust`, where the corridor layer is one input of four
and the win may not survive the blend.

The MAEs above are not comparable to the 118 s that `full` reads in
`reports/approaches.md`. A sweep scores on the common support of its own points,
which here is a different and larger set of crossings.

## The shape of the model findings

Finding 7 stands apart - it is a defect in the measuring, not a property of the
city or the model. Three distinct mechanisms account for the others.

1. **A prior is only worth its bias.** Findings 1, 2, 6 and 8. The timetable is
   used as a level and its level is wrong by 6%, so every cell without live
   evidence inherits that error. Shrinkage does not rescue a biased target; it
   delivers it - and the nightly shutdown puts the whole network back into that
   state once a day. Finding 8 sharpens this: the harm is in the shrinkage, not
   in the prior, and loosening the one makes the other stop mattering.
2. **Resolution is worthless faster than it is refreshed.** Findings 2, 3, 8 and
   13. Cells and short half-lives both describe the city more finely than 11.5
   crossings per cell per recording can support, and a fixed shrinkage
   constant then throws most of that description away. Finding 13 finds the
   other edge of the same trade: a 400 m speed cell and a 90 degree heading
   class are each coarse enough to average over two different roads, and both
   cost about 1 s.
3. **A correction is only valid over the time it persists.** Findings 4, 5, 6,
   8, 9, 10, 11 and 12. A vehicle's offset lasts 5 minutes and is applied over 45; the
   operator's position error lasts as long as its position is wrong and is
   applied to everything downstream of it; the road model's own memory lasts 90
   minutes, which is shorter than the night it has to be carried across; and a
   tuned model that remembers for twelve hours carries the current state of the
   road 45 minutes ahead of itself, which is where its only loss is. Finding 9
   is the same mechanism one level up: a correction fitted on the evening is
   good for the short horizons of the next morning and loses 44 s at the long
   ones, because that is how far the regime it was fitted in reaches. Finding
   10 is the sharpest version of it, because it separates the two things a
   fitted rule can learn: the *level* of the evening's error does not survive
   the night at all (fitting only that costs 9.5 s), while which member is
   better at which horizon does, and is worth 9 to 14 s. Finding 11 is the
   remedy read off the same mechanism: give the memory a term that lasts longer
   than the gap it must cross, and the morning it kept losing is worth 18%.

Finding 12 adds a fourth, smaller one. **A fit that cannot resolve the tail
shrinks toward the middle, and an interval is all tail.** The fitted 0.1/0.9
pair is narrower than the empirical one at every horizon and undercovers by 13
to 21 points. The same shrinkage that makes a point estimate safe - and at
midday `resid-quantile` is the best point model there is - makes a band wrong.

The one thing to take away: every one of these is a mismatch between how long a
piece of evidence is good for and how far it is being carried.
