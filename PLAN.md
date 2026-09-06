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
3. **Sample size.** About 63 000 crossings and 920 000 paired predictions in the
   current scored window, but they are not 920 000 independent facts: a vehicle
   running late is late at every stop ahead of it, and the effective count is
   nearer the number of trips. A model with more than a few hundred effective
   parameters will fit noise. Report bootstrap intervals, which `score.bootstrap`
   already does by resampling whole trips, and treat any gap smaller than its
   interval as no result.

**Rerun the whole comparison once the recording covers three full weekdays.** The
current numbers are a screening pass, not the answer.

## Rules every new approach must obey

- **Tracking must stay variant-independent.** `experiments.py:57` asserts that
  every variant produced the same `res.truth` keys, and the paired scoring in
  `score.paired` depends on it. So no approach may change `track.py`. Anything
  that wants different ground truth is a different experiment, not a variant.
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
`config.py`. Screening scores below are one hour of replay (2026-09-06
07:00-08:30, warmup 1800 s, 23667 paired predictions) and are not the final
numbers - Phase 1 has to be rerun with the rest of the comparison.

- [x] **`no-prior` + `sections`** - finding 2 says `sections` mostly wins by not
      paying the prior's bias, so the combination should beat either. Pure config
      change: `replace(FULL, unit="section", corridor=False, prior="off")`.
      **MAE 100 s against `full`'s 106 s, and the bias goes +26 to -33.** The
      best of the three, and it stays best at every horizon over 2 minutes.
- [x] **`prior-shape`** - finding 1's remedy. Keep the timetable prior as a shape
      but not as a level: normalise it so its length-weighted mean equals the
      learned global pace rather than the timetable's own. `PaceModel._level`
      does the rescale once at construction; `Config.prior` is now
      `"level" | "shape" | "off"`. **MAE 104 s, bias +26 to +18.** So the level
      is part of what the prior costs but not all of it - `sections-no-prior`
      drops the prior entirely and still wins by 4 s.
- [x] **`offset-decay`** - finding 4's remedy. `_factor` in `replay.py` multiplies
      the whole remaining ETA flat, but a vehicle's own speed ratio has an
      e-folding time near 4.5 minutes. `replay._fade` now scales each leg by
      `exp(-h / 300)` at that leg's own lead time `h`, so the next stop gets the
      ratio in full and the far end gets none. **MAE 130 s to 103 s** - it turns
      the worst variant into the second best. At 20-45 min `vehicle-offset`
      scores 383 s and `offset-decay` 269 s, which is the fade doing exactly
      what it was built to do.

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
| `fast_hl` | `config.py` | 480 s | 120, 300, 480, 900, 1800 | how live "live traffic" is |
| `slow_hl` | `config.py` | 5400 s | 1800, 5400, 14400, 43200 | how long the baseline remembers |
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
      already was. Extended grids and `k_corr` are running.
- [x] **The `fast_hl` confound is settled.** At `fast_hl = 7200` the fast term
      nearly coincides with the 5400 s slow one, so the gain could have been
      half as much shrinkage rather than longer memory. Sweeping `fast` on a
      base with `fast_hl = 7200`: off costs +9.1 s [+7.8, +10.2]. The term earns
      its place; it just wants a much longer half-life than it ships with.
- [ ] **Read the direction, not the numbers.** A slow half-life of two days on
      an 8.5-hour recording is not decay at all, and `k_unit = 1` on top of it
      says the cell should be trusted almost immediately. Both are the same
      claim: on this much data the model is throwing away evidence. Whether that
      survives a recording spanning several days is Phase 6's question, and no
      default should move before then.

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
      beats `full` the model has a bias, which finding 1 says it does (+36 s).
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
