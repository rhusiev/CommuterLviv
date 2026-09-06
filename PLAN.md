# Plan: a fuller comparison of approaches

**Reread this file after every compaction.** It is the working plan for the
approach exploration, not a report. `reports/approaches.md` holds the scores and
`reports/findings.md` holds why they came out that way.

Status key: `[ ]` not started, `[~]` in progress, `[x]` done and scored,
`[-]` tried and dropped (with the reason kept).

## Phase 0 - three scoring defects, found while running Phase 3

All three were in how an answer is matched to a crossing, not in any model, and
all were fixed before any Phase 4 work. **Every score quoted below them in this
file, and every number in `reports/approaches.md` and `reports/sweeps.json`
written before 2026-09-06, was produced under one or more of them.** Finding 7
in `reports/findings.md` is the full account.

- [x] **The arrivals board was setting the common support.** `lad` answers about
      only the 40 stops the collector polls, and it was inside the intersection,
      so the headline table judged every approach on 12% of its predictions - all
      of them near those 40 stops. `score.paired` now excludes it by name and it
      gets its own table.
- [x] **Ground truth was being deleted by the arrivals board's naming.** A
      crossing was kept only if *both* (trip, stop) and (vehicle, stop) named it
      uniquely. Over a six-hour window a vehicle passes each of its stops several
      times, so (vehicle, stop) is unique for only 11% of crossings against 94%
      for (trip, stop): 89% of the ground truth was being thrown away to
      accommodate the one predictor that needs the weaker naming. Worse, our own
      predictions were addressed by (trip, stop) too, so a prediction about one
      pass could be scored against a different pass of the same trip. `Truth` now
      keeps every crossing keyed by (vehicle, trip, pass, stop) and
      `predictors.ours` uses that full key.
- [x] **A partial name is settled by when the predictor spoke, not by
      uniqueness.** Keeping only the crossings a name picks out uniquely was the
      first repair and it was the wrong one - it still discarded crossings for
      the benefit of the weakest namer. A prediction made at `t` about a stop is
      about the next crossing of that stop at or after `t`, which uses only the
      time the predictor spoke and never the value it gave. `Truth.Index` is that
      lookup. Coverage: `schedule` 94% to 100%, `api` to 95%, `lad` 1.7% to 17.8%.
- [x] **A snapshot feed was being read as a change log.** `_from_log` let a
      published value stand until replaced, which is right for `trip_updates` (a
      change log) and wrong for the arrivals board (a 60 s snapshot of what it
      displayed). Board values hours old were being scored. `_from_log` now takes
      a staleness bound, 120 s for the board. This is the fix that changes a
      published conclusion: the board is several times better than `api`, not
      beside it.

## Where the comparison stands, on the corrected run

2026-09-06, 80 572 crossings over 1056 minutes, 1 318 685 predictions every
approach answered. Overall MAE, best first, from `reports/approaches.md`:

| | s | | s | | s |
|---|---|---|---|---|---|
| `no-prior` | 114 | `no-fast` | 122 | `table` | 134 |
| `prior-shape` | 118 | `no-incremental` | 122 | `k-split` | 140 |
| `knn` | 118 | `sections-no-prior` | 127 | `vehicle-offset` | 163 |
| **`full`** | **119** | `no-hold` | 130 | `median` | 174 |
| `offset-decay` | 121 | `no-corridor` | 132 | `schedule-offset` | 208 |
| `sections` | 121 | `table-live` | 134 | `api` | 467 |

Nothing beats `full` by more than 4%, and the two that do - `no-prior` and
`knn` - both win by *removing* structure. Read that as the standing summary: on
8.5 hours of one day, every piece of machinery in the shipped model is either
neutral or slightly harmful, and the ablations that cost real accuracy are only
`hold` (+9%), `corridor` (+11%) and the shared shrinkage constant (`k-split`,
+17%). The plan from here is not to find a better model but to find out which of
these survive a recording that spans several days, which is Phase 6.

The one outside predictor worth beating is the public arrivals board, not `api`:
on the 161 466 events it also answers, `lad` scores 111 s and `api` 408 s, with
`full` at 85 s.

## Speed of the comparison

A seventeen-variant run took about 49 minutes because 73% of each replay is
`track.observe` rebuilding vehicle tracks, and `observe` takes no config, so all
seventeen rebuilt identical tracks. `replay.run_many` now forks one worker per
variant instead, and `experiments.run_all` and `sweep.run` both go through it.
`check_parallel.py` is the guard: it replays three variants both ways and
compares every array element by element, including the three outside predictors.
Bit-identical, 45.7 s to 18.2 s on those three. Run it after anything that
touches `replay.py`.

- [ ] **Retime a full seventeen-variant run** and record the real figure here.
      The three-variant measurement extrapolates to about 9 minutes at the
      default `cpu_count() - 2` workers, but that is arithmetic, not a
      measurement, and memory bandwidth is the obvious way for it to be wrong.
- [-] **A single tracking pass shared by every variant.** Dropped. It would take
      the remaining 9 minutes to about 5, and costs a restructuring of
      `replay.py` - the file every published number rests on - plus per-variant
      shadow state for `Cell.sent_d`/`sent_w` and a tape of roughly 3M Python
      tuples that fork's copy-on-write would then duplicate in every worker. Not
      worth four minutes. It composes with the parallelism if that ever changes.
- [-] **A closed-form 2x2 Kalman inverse** (~10% of `observe`) and **precomputing
      `ab`/`l2` on `Shape`** (~8%). Dropped: both change results in the last bits,
      and this comparison's whole method is that every variant sees identical
      tracking. The second also invalidates the pickled `network.pkl`.

## The question all of this answers

Which way of turning recorded GPS fixes into an arrival time is most accurate on
this network, and how much of the accuracy comes from the physical model, from
online learning, and from offline learning?

Three families have to be represented, because the answer is not obvious in
advance:

- **no learning** - the timetable, and the timetable plus a lateness
- **online learning** - what ships now: exponentially weighted means over the
  road, updated as fixes arrive, never fitted offline
- **offline learning** - a model fitted on past days and applied to a later one,
  which is what "ML" means here
- **hybrid** - a physical model for the level, an offline model for the residual

## What the data allows, and what it does not

`data/feed.db` at the time of writing covers two windows: 2026-09-05 20:00-23:59
and 2026-09-06 00:00-09:32, of which about 8.5 hours carry moving traffic. There
is no data at all for 10:00-19:00, and none for a second weekday. The collector
is running and this grows by roughly 14 usable hours a day.

Three consequences, and they bind every ML item below:

1. **An offline model fitted and scored on this recording is measuring itself.**
   Any variant that fits parameters offline must be fitted on the evening window
   and scored on the morning window, never on both. That split is conservative -
   an evening peak is not a morning peak - which is the right direction to err.
2. **Anything keyed by day-of-week or by hour-of-day outside 05-09 and 20-23 is
   currently unfittable.** Finding 6's proposed fix - a hour-of-day by day-of-week
   profile learned across days - cannot be evaluated until the recording spans
   several days. Build it, hold the score.
3. **Sample size.** 80 572 crossings and 1 318 685 paired predictions in the
   current scored window, but they are not 1.3M independent facts: a vehicle
   running late is late at every stop ahead of it, and the effective count is
   nearer the number of trips. A model with more than a few hundred effective
   parameters will fit noise. Report bootstrap intervals, which `score.bootstrap`
   already does by resampling whole trips, and treat any gap smaller than its
   interval as no result.

**Rerun the whole comparison once the recording covers three full weekdays.** The
current numbers are a screening pass, not the answer.

## Rules every new approach must obey

- **Tracking must stay variant-independent.** `replay.run_many` hashes each
  variant's ordered `res.truth` keys and refuses a set that disagrees, and the
  paired scoring in `score.paired` depends on that holding. It is also what
  makes the parallel replay safe. So no approach may change `track.py`.
  Anything that wants different ground truth is a different experiment, not a
  variant.
- **Causality.** `replay.run` is one forward pass and the model is only ever read
  after the epoch's observations are folded in. An offline-fitted model is
  causal only if its training data ends before the scored window starts. Assert
  that in code, do not rely on remembering it.
- **One change at a time.** Every variant differs from `full` in exactly one
  place, except where the point is the combination, and then the single-change
  variants for both halves must exist too.

## Phase 1 - the three fixes the findings already argued for

These come out of `reports/findings.md` and cost nothing to test. Do them first;
they may move the baseline that everything else is compared against.

All three land as `sections-no-prior`, `prior-shape` and `offset-decay` in
`config.py`. Two sets of numbers appear below. The **screening** scores were one
hour of replay (2026-09-06 07:00-08:30, warmup 1800 s, 23667 paired predictions)
under the old scoring; the **full** scores are the 2026-09-06 run over the whole
recording with Phase 0's fixes in, and those are the ones that count.

**All three fixes were wrong about the outcome, and none is a win.** The
screening pass ranked `sections-no-prior` best of everything; on the corrected
full run it is 127 s against `full`'s 119 s, the worst of the three. That
reversal is not the fixes changing their behaviour - it is what an hour of one
morning, scored on 12% of its predictions, is worth as evidence. Keep all three
variants in the comparison as evidence; ship none of them.

- [x] **`no-prior` + `sections`** - finding 2 says `sections` mostly wins by not
      paying the prior's bias, so the combination should beat either. Pure config
      change: `replace(FULL, unit="section", corridor=False, prior="off")`.
      Screening: MAE 100 s against `full`'s 106 s. **Full: 127 s against 119 s,
      worse than either parent** (`sections` 121, `no-prior` 114). Dropping the
      prior helps a cell model, which has a corridor to fall back on, and hurts
      a section model, which has only the global mean. Both changes spend the
      same thing.
- [x] **`prior-shape`** - finding 1's remedy. Keep the timetable prior as a shape
      but not as a level: normalise it so its length-weighted mean equals the
      learned global pace rather than the timetable's own. `PaceModel._level`
      does the rescale once at construction; `Config.prior` is now
      `"level" | "shape" | "off"`. Screening: MAE 104 s. **Full: 118 s against
      `full`'s 119 s and `no-prior`'s 114 s.** So the level is part of what the
      prior costs but not all of it: normalising it recovers a fifth of the gap
      to dropping the prior outright. The shape is worth about nothing.
- [x] **`offset-decay`** - finding 4's remedy. `_factor` in `replay.py` multiplies
      the whole remaining ETA flat, but a vehicle's own speed ratio has an
      e-folding time near 4.5 minutes. `replay._fade` now scales each leg by
      `exp(-h / 300)` at that leg's own lead time `h`, so the next stop gets the
      ratio in full and the far end gets none. Screening: MAE 130 s to 103 s.
      **Full: `vehicle-offset` 163 s to `offset-decay` 121 s, against `full`'s
      119 s.** The fade does exactly what it was built to do - 20-45 min goes
      325 s to 219 s, level with `full`'s 212, while 0-1 min stays at 16 s
      against `full`'s 17 - and the result is a tie. The vehicle's own recent
      speed knows nothing about the next two minutes that the corridor-fast term
      does not already know. This is the cleanest negative result in the plan:
      correct diagnosis, correct fix, no gain.

## Phase 2 - hyperparameters of the estimator that ships

- [x] **Move them into `Config`.** `K_CELL` and `K_CORR` are gone from `model.py`
      and are now `Config.k_unit` / `Config.k_corr`; `fast_hl` and `slow_hl` are
      no longer `PaceModel.__init__` arguments but `Config` fields. Defaults are
      the shipped values, so nothing moved. `Layer` takes `k_unit` and `k_corr`
      per instance.
- [x] **A command to sweep them.** `python3 -m lvivpred sweep <field> [values]`
      cold-replays one point per value and prints a paired 95% interval against
      the best point, appending the grid to `reports/sweeps.json`. Paired rather
      than absolute because on a grid this tight the shared variance is nearly
      all of it and six absolute intervals would all overlap.

| constant | where | now | sweep | what it decides |
|---|---|---|---|---|
| `k_unit` | `config.py` | 4.0 | 0.5, 1, 2, 4, 8, 16 | how much evidence a cell needs before it outweighs its corridor |
| `k_corr` | `config.py` | 4.0 | 0.5, 1, 2, 4, 8, 16 | same, corridor against global |
| `fast_hl` | `config.py` | 480 s | 480 to 57600 | how live "live traffic" is |
| `slow_hl` | `config.py` | 5400 s | 5400 to 691200 | how long the baseline remembers |
| `RATIO_CLIP` | `model.py:46` | (0.15, 8.0) | (0.4, 2.5), (0.25, 4) | how much of an outlier a crossing may be |
| `MAX_HOLD` | `track.py:29` | 240 s | 60, 120, 240, 600 | where a layover stops counting as traffic |

The last two are still module constants; move them the same way when their turn
comes.

- [x] **First pass, on the fixed ground truth** (69 929 crossings, 986 epochs,
      `reports/sweeps.json`). Every shipped value lost, and three of the four
      grids point the same way - **less shrinkage, longer memory**:
      `k_unit` 4.0 to **1.0** (149 s to 139 s; 0.5 not separated from 1.0),
      `fast_hl` 480 s to **7200 s** and `slow_hl` 5400 s to **172800 s**, both
      of which ran to the top of their grid, `knn` **10**, which is what it
      already was.
- [x] **Second pass, extended grids and `k_corr`** (87 036 crossings, 1 099
      epochs, so its MAE is on a different support from pass 1's and from the
      experiment's - compare within a pass only). Two of the three grids stopped
      running to their edge:
      `fast_hl` **plateaus**: 480 → 168.4, 1800 → 165.0, **7200 → 164.2**,
      14400 → 164.4, 28800 → 164.3, 57600 → 164.3, with nothing at or above
      7200 separated. Bias worsens monotonically across the whole grid, -56.1 to
      -96.4, so the plateau is where a longer memory stops helping the size of
      the error and keeps hurting its sign.
      `slow_hl` is **flat past 43200**: 5400 → 168.4, 43200 → 166.5,
      **172800 → 166.4**, 345600 → 166.4, 691200 → 166.4. A half-life longer
      than the recording is indistinguishable from no decay at all, which is
      what those last three points are.
      `k_corr` is **still at the lower edge**: **0.5 → 166.5**, 1 → 166.7,
      2 → 167.1, 4 → 167.8, 8 → 169.0, 16 → 170.6 - monotone, and every step
      separated.
- [ ] **Extend the `k_corr` grid downward** to 0.125 and 0.25. It is the one
      grid that has not turned over, so its optimum is not yet measured, only
      bounded above.
- [ ] **Score a combined `tuned` variant** - `k_unit=1`, `k_corr=0.5`,
      `fast_hl=7200`, `slow_hl=43200` - against `full`, `no-prior` and `knn` on
      the experiment's support. The four grids were each swept with everything
      else shipped, so their gains are not known to add. This is also the
      decisive question of the whole comparison so far: whether tuning the
      structure beats removing it. Cheap now that variants run in parallel.
- [x] **The `fast_hl` confound is settled.** At `fast_hl = 7200` the fast term
      nearly coincides with the 5400 s slow one, so the gain could have been
      half as much shrinkage rather than longer memory. Sweeping `fast` on a
      base with `fast_hl = 7200`: off costs +9.1 s [+7.8, +10.2]. The term earns
      its place; it just wants a much longer half-life than it ships with.
- [ ] **Read the direction, not the numbers.** All four grids say the same
      thing - less shrinkage, longer memory - and a slow half-life longer than
      the recording is not decay at all. On a single day that is exactly the
      shape you would see if there were no genuine within-day variation worth
      tracking: nothing to forget, so forget nothing, and nothing local to
      learn, so pool everything. It is also exactly the shape you would see if
      the recording were simply too short to show that variation. Those two are
      not distinguishable here; Phase 6 is what separates them, and no default
      should move before then.

      The same reading applies to `knn` (118 s) sitting a second ahead of
      `full` (119 s) in the comparison. It has no hierarchy, no decay and no
      prior - a plain median of the last 10 crossings - so it is the strongest
      single piece of evidence that this recording's structure is thinner than
      the model assumes. It is the first thing to re-score on a multi-day
      recording.

Finding 3 is the specific hypothesis to test here: the cell-fast term supplies
8.3% of the blend and is diluted almost to nothing by `K_CELL = 4.0`, so a
**per-layer K** - small at the corridor, large at the cell - should beat one
shared constant. That is the `k-split` variant (`k_unit=16`, `k_corr=1`), to be
scored with the rest of the comparison before the grid is run.

Geometry constants cost a network rebuild and go last, in their own pass:

- [ ] `CELL` (`network.py:19`, 100 m) at 50, 100, 200, 400 m. Finding 2 measured
      the between-cell variance at 59% of the total against 37% between-section,
      so there is a resolution optimum somewhere between the two and neither end
      is it.
- [ ] `CORRIDOR_GRID` (`network.py:20`, 120 m) at 60, 120, 250 m, and the bearing
      resolution at 4, 8, 16 octants.

Sweeps are not free: each is a full replay. Run them as a batch overnight rather
than interactively, and write the grid to `reports/sweeps.json`.

## Phase 3 - approaches with no online learning at all

The point of these is to bound how much the online part is worth. If a static
table fitted on yesterday matches the live model, the live model is doing
nothing that a lookup could not.

**Answered, on the corrected full run.** The online part is worth roughly 12%,
and no more than that: `table` 134 s and `table-live` 134 s against `full`'s
119 s. A frozen (section, hour) lookup gets within an eighth of the shipped
model, and the single global today-is-slow multiplier that `table-live` adds on
top buys nothing measurable. Meanwhile `knn` - the last 10 crossings of the
section, median, no hierarchy and no decay at all - scores 118 s and beats
`full`. So the cell/corridor/global back-off structure is not paying for its
complexity against a plain recency window on this recording. That is the single
most consequential result of the whole comparison so far, and it is the thing to
re-test first when the recording covers several days: a recency window is
exactly what should degrade when the sparse hours arrive.

- [x] **`table`** - one travel time per (section, hour-of-day), fitted offline on
      the training window, applied frozen. No decay, no updates, no back-off.
      This is the classic "historical average" baseline every transit paper uses
      and it is missing from the comparison. Implemented as
      `baselines.TableModel`; the fit stops the epoch scoring starts, which
      `replay._flush` signals by setting `model.emitting`.
- [x] **`table-live`** - the same table, plus a single global multiplier tracking
      today's overall speed against it. One number of online learning, to see how
      much of the benefit is just knowing whether today is fast or slow.
- [x] **`knn`** - for the section and hour being predicted, the median of the
      last `k` crossings of that section by any vehicle, with no shrinkage
      hierarchy at all. `k` in 3, 5, 10, 20. Tests whether the whole
      cell/corridor/global back-off structure earns its complexity against a
      plain recency window. Implemented as `baselines.KnnModel`; `k` still to be
      swept.
- [x] **`median`** - swap every EWMA mean for a decayed weighted median. MAE is
      minimised by the median, not the mean, and the current model optimises the
      wrong loss throughout. Cheap to state, awkward to implement vectorised -
      approximate with a decayed P-square or a small per-unit ring buffer.
      Implemented as `baselines.MedianModel` over a per-key ring buffer of the
      last `cfg.ring` crossings; the decay is applied to each entry's weight, so
      the two half-lives survive. Best of everything at 0-5 min and the worst at
      10-45 min, with a bias no median convention removes: an ETA is a *sum* of
      cell times, and a sum of medians of right-skewed times runs short.

## Phase 4 - offline learning on the residual

This is where "ML" earns or fails to earn its place. The target is not the
arrival time - predicting that from scratch throws away a physical model that is
already within 2 minutes - but **the residual of the shipped model**, in log
space so it is a multiplicative correction.

Setup, common to all of Phase 4:

- **Target** `log((actual - now) / max(predicted - now, 1))`, clipped at ±1.5
- **Split** fit on 2026-09-05 20:00-23:59, score on 2026-09-06 05:30-09:32
- **Rows** one per emitted prediction, which is about 920 000 in the scored
  window; the training window has its own count, expect the same order
- **Features**, all available causally at emit time:
  `horizon` (seconds to the predicted arrival), `n_stops_ahead`,
  `dist_remaining`, `hour + minute/60`, `model_eta`, the vehicle's own speed
  ratio `_factor` and its age, the cell-fast and cell-slow effective weights
  along the path, the corridor-fast weight, `route_id`, `sched_headway`,
  the timetabled travel time for the same span, and current lateness against the
  timetable
- **Weighting** by `1 / truth.gap` so a crossing interpolated across a 40 s hole
  counts less than one pinned to 10 s

Models, in increasing order of what they can express. Each is scored against the
uncorrected `full` and against the one above it, so the comparison says what the
extra capacity bought:

- [ ] **`resid-const`** - one number: the mean residual. A sanity floor. If this
      beats `full` the model has a bias. Pooled, `full`'s bias is only -9 s, but
      that is two biases cancelling: +6 s at 0-1 min and -69 s at 20-45 min. So
      fit the constant per horizon bucket, not once - a single number would find
      nothing here and would be the wrong test.
- [ ] **`resid-linear`** - ridge regression on the features above. Closed form in
      numpy, no dependency. Tells whether the residual is a linear function of
      horizon and lateness, which is the shape finding 4 predicts.
- [ ] **`resid-gbm`** - gradient-boosted regression trees, squared loss and then
      absolute loss. Needs `scikit-learn` (`HistGradientBoostingRegressor`);
      **add it as an optional extra, not to `requirements.txt`**, so the
      collector's VPS footprint does not change. Tune `max_depth` in 3-8,
      `learning_rate` in 0.03-0.3, `max_iter` by early stopping on a held-out
      slice of the *training* window.
- [ ] **`resid-quantile`** - the same GBM at quantile 0.5, and at 0.1/0.9 to get
      a prediction interval. An interval is a genuinely new output: "the bus
      arrives in 6-11 minutes" is more useful than a point estimate that is
      wrong by 90 seconds, and nothing currently produces one.
- [ ] **`resid-mlp`** - a small dense network, two hidden layers of 32-64 units.
      Expected to lose on 16k rows; run it anyway so the report can say by how
      much rather than assert it. Needs `torch`, or write the backward pass in
      numpy - it is small enough that numpy is the lighter option.

Feature ablation on whichever of these wins, so the report can say *which*
feature carried it rather than just naming the model.

## Phase 5 - hybrid and ensemble

- [ ] **`stack`** - fit per-horizon-bucket blend weights over `full`,
      `no-prior`, `sections` and `api`, on the training window. The buckets are
      already defined in `score.py:BUCKETS`. Finding 4 showed `vehicle-offset`
      wins at 0-1 min and loses at 20-45, and finding 5 showed `api` has a good
      median and a bad tail, so a horizon-aware blend of things that fail
      differently is the most likely single win in this whole plan.
- [ ] **`stack-robust`** - the same, but blending medians rather than means, to
      stop the `api` tail from poisoning the mix.
- [ ] **`full` + `resid-gbm`** - the best physical model with the best residual
      model on top. This is the headline hybrid.

## Phase 6 - the multi-day items, blocked on data

Build now, score when the recording covers three weekdays. Note in the report
that they are unscored rather than quietly omitting them.

- [ ] **`profile`** - finding 6's fix. A persistent hour-of-day by day-of-week
      pace profile per section, learned across days, sitting beneath the two
      EWMAs as the thing they back off to instead of the timetable prior. This
      directly addresses the nightly reset, which finding 6 measured as `full`
      opening the morning peak believing the city is 15% slower than it is.
- [ ] **`slow-day`** - the cheaper half of the same idea: a third EWMA with a
      half-life of a day or two, so something survives the overnight gap without
      needing a full profile.
- [ ] **Per-hour scoring.** No per-hour table is published today, which finding 6
      noted is why nothing shipped is misleading despite the sparse hours. Once
      there are enough hours, publish MAE by hour with counts, and suppress any
      hour with fewer than a few hundred paired predictions rather than printing
      a number nobody should read.

## Deliverables

- `reports/approaches.md` regenerated with every scored variant, keeping the
  existing paired-on-common-support method and bootstrap intervals
- `reports/sweeps.json` with the hyperparameter grids
- a section in `reports/findings.md` for whatever the new results contradict
- this file, kept current: mark each item as it lands, and keep the reason when
  something is dropped
