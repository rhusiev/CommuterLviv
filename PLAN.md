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
      times, so (vehicle, stop) is unique for only 11% of predictions against 94%
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

## Where the comparison stands

2026-09-06, 93 796 crossings over 1143 minutes, 1 756 722 predictions every
approach answered. Overall MAE, best first, from `reports/approaches.md`:

| | s | | s | | s |
|---|---|---|---|---|---|
| **`tuned`** | **114** | `offset-decay` | 122 | `no-corridor` | 132 |
| `no-prior` | 115 | `no-fast` | 123 | `k-split` | 140 |
| `prior-shape` | 119 | `no-incremental` | 123 | `table-live` | 144 |
| `full` | 120 | `sections-no-prior` | 128 | `table` | 149 |
| `knn` | 121 | `no-hold` | 131 | `vehicle-offset` | 165 |
| `sections` | 122 | | | `median` | 177 |

`schedule-offset` 199, `api` 471, `schedule` 843.

**`tuned` is the first thing to actually beat `full`, and it does it by tuning
rather than by removing.** It is the shipped model at the best value each of its
four constants found when swept alone - `k_unit=1`, `k_corr=0.5`,
`fast_hl=7200`, `slow_hl=43200` - so the four gains do add, at least to a 5%
total. It wins every horizon bucket out to 20 minutes and by a widening margin:
15 s against 18 at 0-1 min, 39 against 48 at 2-5, 65 against 78 at 5-10, 111
against 126 at 10-20. It loses only the last bucket, 223 against 214 at 20-45
min, and the absolute intervals there overlap.

That last bucket is the price, and the bias column says what is being bought:
`tuned` runs at -66 s against `full`'s -10. Trusting live evidence sooner and
forgetting it later means the model tracks whatever the road is currently doing
and carries it far further ahead than it should, which is free at three minutes
and wrong at thirty.

**`tuned` and `no-prior` are the same finding twice.** They score 114 against
115 with bias -66 against -63 and sit within a second of each other in five of
six buckets, having got there by opposite routes: one keeps the timetable prior
and stops shrinking towards it, the other deletes it. Turning the prior off *on
top of* the tuned constants settles it (`check_prior.py`, four variants on one
common support of 94 376 crossings):

| bucket | `full` | `tuned` | `tuned-no-prior` | `no-prior` |
|---|---|---|---|---|
| 0-1 | 18 | 15 | 15 | 16 |
| 1-2 | 30 | 25 | 24 | 25 |
| 2-5 | 49 | 40 | 39 | 41 |
| 5-10 | 80 | 67 | 65 | 69 |
| 10-20 | 130 | 115 | 113 | 117 |
| 20-45 | 224 | 234 | 239 | 230 |

Deleting the prior costs `full` 2 s at 0-1 min and 13 s at 10-20; it costs
`tuned` 0 s and 2 s. **The prior is nearly inert once the shrinkage is
loosened** - which is what "the learned pace dominates it" means, and it is the
mechanism behind both results. So there is one thing to carry into Phase 6, not
two: on a single day the model shrinks too hard towards a prior it does not
need. Whether it still does not need it across several days is the whole
question.

Everything else still holds: the ablations that cost real accuracy are only
`hold` (+9%), `corridor` (+9%) and the shared shrinkage constant (`k-split`,
+17%), and no default should move before Phase 6 shows which of this survives a
recording spanning several days. A constant tuned on one day is fitted to that
day.

The one outside predictor worth beating is the public arrivals board, not `api`:
on the 212 763 events it also answers, `lad` scores 114 s and `api` 429 s, with
`full` at 87 s.

## Speed of the comparison

A seventeen-variant run took about 49 minutes because 73% of each replay is
`track.observe` rebuilding vehicle tracks, and `observe` takes no config, so all
seventeen rebuilt identical tracks. `replay.run_many` now forks one worker per
variant instead, and `experiments.run_all` and `sweep.run` both go through it.
`check_parallel.py` is the guard: it replays three variants both ways and
compares every array element by element, including the three outside predictors.
Bit-identical, 45.7 s to 18.2 s on those three. Run it after anything that
touches `replay.py`.

- [x] **Retimed on the real thing.** The eighteen-variant run of 2026-09-06:
      six workers on eight cores, per-variant times 213-282 s with a mean of
      232, three waves, about 12 minutes of replay. Sequential would be 70. The
      per-variant time is roughly 30% above the 170-180 s the same variants take
      when only four run at once, so contention is real and the speedup is
      nearer 6x than the 8x the worker count suggests - which is the direction
      the earlier three-variant extrapolation got wrong. End to end - replay,
      the three outside predictors, paired scoring and the bootstrap intervals -
      the run took 16 min 41 s, 15:19:38 to 15:36:19, so scoring is about a
      quarter of the wall time and is the next thing that would have to be
      attacked, not the replay.
- [-] **A single tracking pass shared by every variant.** Dropped. It would take
      the replay phase from about 12 minutes to about 6, and costs a
      restructuring of `replay.py` - the file every published number rests on -
      plus per-variant shadow state for `Cell.sent_d`/`sent_w` and a tape of
      roughly 3M Python tuples that fork's copy-on-write would duplicate in
      every worker. Not worth six minutes, and less so now that scoring is a
      quarter of the run. It composes with the parallelism if that ever changes.
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
- [x] **A command to sweep them.** `python3 -m commuterlviv sweep <field> [values]`
      cold-replays one point per value and prints a paired 95% interval against
      the best point, appending the grid to `reports/sweeps.json`. Paired rather
      than absolute because on a grid this tight the shared variance is nearly
      all of it and six absolute intervals would all overlap.

| constant | where | now | sweep | what it decides |
|---|---|---|---|---|
| `k_unit` | `config.py` | 4.0 | 0.5, 1, 2, 4, 8, 16 | how much evidence a cell needs before it outweighs its corridor |
| `k_corr` | `config.py` | 4.0 | 0.125 to 4 | same, corridor against global |
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
- [x] **Extended the `k_corr` grid downward** to 0.125 and 0.25 (92 944
      crossings, 1 138 epochs - the recording had grown again, so this is a
      third support and a third set of MAEs not comparable to the two above).
      Still monotone to the lower edge and every step still separated:
      **0.125 → 168.8**, 0.25 → 169.0, 0.5 → 169.1, 1 → 169.3, 2 → 169.8,
      4 → 170.6. But the whole grid now spans 1.8 s and the three best points
      span 0.3 s, against a `full` MAE near 169. The direction is real and the
      size of it is not worth a default change: `k_corr` is a nearly flat
      direction, and the separations only reach significance because a paired
      bootstrap over identical rows has almost no variance left to hide them.
      Reading a separated interval as an important one is the mistake this
      point exists to record. Stop sweeping it.
- [x] **Score a combined `tuned` variant** - `k_unit=1`, `k_corr=0.5`,
      `fast_hl=7200`, `slow_hl=43200` - against `full`, `no-prior` and `knn` on
      the experiment's support. The four grids were each swept with everything
      else shipped, so their gains are not known to add. This is also the
      decisive question of the whole comparison so far: whether tuning the
      structure beats removing it. **They do add, to about 5%**: `tuned` 114 s
      against `full`'s 120 and `no-prior`'s 115, winning every horizon bucket
      out to 20 minutes and losing only 20-45. It is the first thing to beat
      `full` by tuning rather than by removing; the section above this one has
      the buckets and what the bias says about them.
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

Geometry constants were expected to cost a network rebuild and to go last, in
their own pass. They cost much less than that: the stop assignment that
dominates a build does not depend on any of them, and neither does tracking or
the ground truth, so `network.regrid` recomputes the three affected arrays per
shape and the sweep runs like any other. The three now live in a `Geometry`
dataclass (`network.py`) with `sweep.GEOMETRY` naming them, and `run_many`
accepts one network per config.

All three are run. Finding 13 has the tables; between them they are worth 2 s of
166, and only `grid` is shipped wrong.

- [x] `cell` (was `CELL`, 100 m) at 50, 100, 200, 400 m. Finding 2 measured the
      between-cell variance at 59% of the total against 37% between-section, so
      there is a resolution optimum somewhere between the two and neither end is
      it. It is at 100 m, where the value already was: 166.5 s against 167.8 at
      50, 167.1 at 200 and 168.6 at 400. A shallow U, 2.1 s wide.
- [x] `grid` (was `CORRIDOR_GRID`, 120 m) at 60, 120, 250 m, and `octants`, the
      bearing resolution, at 4, 8, 16. `grid` chose the low edge, so it was
      re-swept at 30, 45, 60, 120: monotone down to 30 (164.4), with 45 (164.7)
      not separated from it and the shipped 120 at 166.7. `octants` 16 (166.7)
      and 8 (166.9) are not separated; 4 costs 1.0 s.
- [ ] Confirm `grid=45` on `stack-robust` before changing `network.DEFAULT`. The
      corridor layer is one input of four there, and a 2.3 s win on `full` need
      not survive the blend.

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
- **Split** one replay of the whole recording, not two, with rows split by the
  time they were emitted: fit on rows before 2026-09-06 00:00 and test from
  05:30 to the end of the recording, which is 18:56. One replay keeps this
  causal - the physical model is causal and the residual model only ever sees
  earlier rows - and it means the model state at 05:30 carries the evening's
  learning, as it would in deployment. Drop the first 40 minutes of training
  rows, where the model is still cold. This split turned out to be too
  lopsided to answer the phase's question on its own; the deviation below says
  what was added and why.
- **Rows** one per emitted prediction: 3 010 244 over the whole recording,
  covering 130 426 crossings
- **Features**, all available causally at emit time:
  `horizon` (seconds to the predicted arrival), `n_stops_ahead`,
  `dist_remaining`, `hour + minute/60`, `model_eta`, the vehicle's own speed
  ratio `_factor` and its age, the cell-fast and cell-slow effective weights
  along the path, the corridor-fast weight, `route_id`, `sched_headway`,
  the timetabled travel time for the same span, and current lateness against the
  timetable
- **Weighting** by `1 / truth.gap` so a crossing interpolated across a 40 s hole
  counts less than one pinned to 10 s

- [x] **The rows themselves.** `commuterlviv/features.py` and a `feats=` hook in
      `replay.run` write one row per emitted prediction, appended in the same
      loop and under the same mask as the prediction, so feature row *i* is
      prediction row *i* and the join to the truth is by position and never by a
      key; `predictors.event_of` supplies the crossing id. Run it with
      `python3 -m commuterlviv features --out reports/feats.npz`. Two deviations
      from the feature list above: `horizon` and `model_eta` are the same
      quantity and only one is recorded, and `fix_age` - how stale the believed
      position is - was added because it is causally available and clearly
      relevant. Three refactors went with it and change no score:
      `predictors.event_of`, `model.integrate` generalised out of `time_between`
      so the same partly-crossed-cell arithmetic serves the evidence-weight
      integrals, and the hook itself. `check_parallel.py` still passes.

Models, in increasing order of what they can express. Each is scored against the
uncorrected `full` and against the one above it, so the comparison says what the
extra capacity bought:

All five landed as `commuterlviv/residual.py` and
`python3 -m commuterlviv residual`, and are scored twice - on the split above, and
on a second split fitted before 12:00 and scored after it. The second split was
not in the plan and is the reason there is a result at all: see the deviation
below. `reports/residual.md` and `reports/residual-midday.md` hold the two
tables, finding 9 holds what they mean. MAE in seconds, plan split first:

| model | plan split | vs full | midday split | vs full |
|---|---|---|---|---|
| `full` | 168.4 | - | 161.2 | - |
| `resid-const` | 197.5 | +29.1 | 163.3 | +2.0 |
| `resid-linear` | 185.0 | +16.6 | 159.7 | -1.5 |
| `resid-gbm` | 207.2 | +38.8 | 154.6 | -6.6 |
| **`resid-quantile`** | 199.3 | +30.9 | **145.5** | **-15.8** |
| `resid-mlp` | 900.9 | +732.6 | 200.5 | +39.2 |

- [x] **`resid-const`** - one number per horizon bucket, fitted per bucket
      rather than pooled because pooled it would find nothing: `full` runs late
      at one minute and early at forty and the two cancel. It is a floor and it
      behaves like one - +2.0 s on the midday split, +29.1 on the plan's. The
      model's bias is not stable enough across the day for a constant to remove
      it.
- [x] **`resid-linear`** - weighted ridge, closed form in numpy, penalty chosen
      on a held-out tail of the training window. The design matrix is never
      materialised: three million rows would be gigabytes and the normal
      equations it feeds are 70 squared, so one chunked pass accumulates them
      and every penalty is solved from the same accumulation. Worth -1.5 s
      [-3.0, -0.3] on the midday split. The residual is not linear in these
      features.
- [x] **`resid-gbm`** - `HistGradientBoostingRegressor`, `max_depth=6`,
      `learning_rate=0.1`, `max_iter=400` with early stopping on 15% held out
      of the training window, `route` passed as categorical. sklearn is imported
      inside the fit and stays out of `requirements.txt`, so the collector's VPS
      footprint does not change. -6.6 s [-13.2, +0.4]: not separated from zero.
- [x] **`resid-quantile`** - the same trees at quantile 0.5. **The winner, and
      the only large step in the whole phase: -15.8 s [-20.1, -11.6], 9.8%.**
      Capacity bought almost nothing and the loss function bought everything -
      the residual is right-skewed, MAE is minimised by the median, and squared
      loss fits one quantity while the scoring grades another.
- [x] **The 0.1/0.9 prediction interval** - `band-const` and `band-quantile`,
      described under the deviations below. Finding 12.
- [x] **`resid-mlp`** - two hidden layers of 48 and 32, Adam in numpy on a
      300k-row subsample, no torch. It loses as expected and by a lot: +39.2 s
      on the midday split and +732.6 on the plan's. Not broken - in-sample it
      cuts training MAE from 135 s to 80 s and correlates 0.67 with the target -
      it overfits the training window and extrapolates.

- [x] **Feature ablation on the winner.** Each group blanked and the model
      refitted, on the midday split. The model's own evidence weights cost
      +20.0 s, the vehicle's speed ratio and fix ages +8.1, the timetable's
      answer and lateness +6.9, hour and route +5.5, and horizon, distance and
      stops ahead +4.5. **How much the model knew is worth more than anything it
      knew**: the correction is learning when the physical model was guessing,
      not learning about the city.

Two deviations from the spec above, both made after seeing the numbers:

- **A second split, fitted before 12:00 and scored after it.** The plan's split
  fits on 141 559 evening rows and scores on 2 757 685 rows covering an entire
  weekday, and on it every model loses. That is a real result about transfer and
  it is kept, but it cannot answer whether a residual model is worth anything at
  all, because the training window is 5% of the test window and a different
  traffic regime. The midday split is still one replay, still strictly causal -
  training rows all precede test rows in emit time - and it is what the 9.8%
  comes from. Neither split is the honest one on its own; the pair is.
- **The 0.1/0.9 interval is a separate pair of rules, not `resid-quantile`
  refitted.** `band-const` is a weighted empirical quantile per horizon bucket
  and fits nothing; `band-quantile` is two quantile-loss tree fits. Graded by
  coverage against the 80% target, mean width and the check loss at each edge.
  `band-const` wins on both splits (76.1% and 82.2% coverage against 59.3% and
  67.2%), because the `1/gap` fitting weight lets a single fit put its edges
  where the short horizons want them. Finding 12.

## Phase 5 - hybrid and ensemble

- [x] **`stack`** - fit per-horizon-bucket blend weights over `full`,
      `no-prior`, `sections` and `api`, on the training window. The buckets are
      already defined in `score.py:BUCKETS`. Finding 4 showed `vehicle-offset`
      wins at 0-1 min and loses at 20-45, and finding 5 showed `api` has a good
      median and a bad tail, so a horizon-aware blend of things that fail
      differently is the most likely single win in this whole plan.
      **The squared-loss fit does not separate from zero on the plan's split:
      117.4 s against `full`'s 116.7, +0.8 [-2.1, +3.7]**, though it is worth
      -12.5 [-14.0, -11.0] on the midday one. It is fitted on 125 841 evening
      rows and scored on 2 391 111 rows of the next day, and the weights it
      learns there do not survive the overnight regime change.
- [x] **`stack-robust`** - the same, but blending medians rather than means, to
      stop the `api` tail from poisoning the mix. **The win of the phase, and the
      largest single one in the plan so far: 107.6 s, -9.0 [-10.3, -7.6], 7.8%,
      on the same split where the squared-loss fit is worthless.** The fit-free
      `stack-median` also transfers, at 111.3 s, -5.4 [-6.3, -4.6]. Both beat
      every member; the best member, `no-prior`, is 112.2 s. On the midday split
      it is -14.4 [-15.7, -13.2], 13.2%, and the control says none of that is
      de-biasing: fitting only the per-bucket intercept is worth +0.3 there and
      +9.5 on the plan's split. Finding 10.
- [x] **`full` + `resid-gbm`** - the best physical model with the best residual
      model on top. This is the headline hybrid. **It is not a hybrid worth
      shipping on this split: 138.2 s, +21.6 [+19.0, +23.9].** On the midday
      split it is worth -9.1 [-11.1, -7.3], less than either fitted stack is
      worth on the identical rows, and it needs a trained model on top of the
      replay rather than six vectors of four weights. That is Phase 4's finding 9 again - the correction is
      fitted on an evening window and applied to a whole weekday - and not a new
      fact, but it is the number the plan asked for.

Implemented in `commuterlviv/stack.py`, run with `python3 -m commuterlviv stack`, with
three deviations from the spec above:

- **The plan's one robustness idea became two rules**, because "blending
  medians" can mean either of two different things and they defend against
  different failures. `stack-robust` fits the same linear weights to minimise
  *absolute* rather than squared error, so no single wild training row sets the
  weights; `stack-median` takes the member-wise median at prediction time, which
  is the only rule a wild `api` value cannot pass through at all. Both are
  scored.
- **The weights are constrained to sum to one, by construction rather than by
  penalty.** One member is the base and the others enter as differences from it,
  so a blend is always an average of predictions and never a rescaling of them,
  and a per-bucket intercept carries whatever shared bias is left.
- **The hybrid uses `resid-quantile`, not `resid-gbm`.** The plan named the
  squared-loss trees before Phase 4 measured that the median-loss ones are the
  only residual model that separates from zero.
- **Both splits are run here too**, for the reason Phase 4 gives, and they
  disagree in the same direction: on the midday split every blend wins, and the
  squared-loss one is nearly as good as the robust one. See finding 10.
- **A fourth rule, `debias`, was added as a control**, because every blend
  carries a per-horizon intercept and the intercepts it fits are large - up to
  +122 s in the 20-45 minute bucket. `debias` fits *only* those intercepts, on
  `full` alone, so the report can say how much of a stack's win is mixing
  predictors and how much is removing a bias the members share.

## Phase 6 - the multi-day items, blocked on data

Build now, score when the recording covers three weekdays. Note in the report
that they are unscored rather than quietly omitting them.

- [ ] **`profile`** - finding 6's fix. A persistent hour-of-day by day-of-week
      pace profile per section, learned across days, sitting beneath the two
      EWMAs as the thing they back off to instead of the timetable prior. This
      directly addresses the nightly reset, which finding 6 measured as `full`
      opening the morning peak believing the city is 15% slower than it is.
- [x] **`slow-day`** - the cheaper half of the same idea: a third EWMA with a
      half-life of a day or two, so something survives the overnight gap without
      needing a full profile. Built ahead of the rest of Phase 6 because the
      recording *contains* one night, so the morning it breaks is scorable now.
      `Config.day_hl` (0.0 = off) adds a third `Ewma` at the cell and corridor
      scales; `Layer` now assembles its terms in `_cells`/`_corrs` instead of
      branching on `fast` in two places. Swept as `day_hl`, whose grid includes
      0 so the sweep carries its own baseline. Scored: warmed on the previous
      evening and night and tested on the morning to 09:00, **109 s against
      `full`'s 134, -18%**, better than `full` at every horizon and better than
      `no-prior` at the two long ones. Over the whole recording, 113 against
      118, tied with `no-prior` and `tuned` on MAE but with a bias of -51 s
      against their -58 and -68 (`reports/slow-day.md`). Finding 11.
- [ ] **Per-hour scoring.** No per-hour table is published today, which finding 6
      noted is why nothing shipped is misleading despite the sparse hours. Once
      there are enough hours, publish MAE by hour with counts, and suppress any
      hour with fewer than a few hundred paired predictions rather than printing
      a number nobody should read.

## Phase 7 - a live service and a web UI

Requested 2026-09-06, to start once Phase 5's follow-ups (the `tuned` member,
`slow-day`, the prediction interval, the geometry sweeps) are finished. This is
the first thing in the project that is a product rather than a measurement, so
it gets its own rules: nothing here may change how a predictor scores, and the
offline replay stays the source of truth about accuracy.

**What it is.** A server that keeps collecting the three feeds, holds the best
current position for every vehicle and the best arrival prediction for every
stop ahead of it, and serves both to a browser in real time. Which predictor
produces those numbers is a backend switch, not a client choice - the same
`config.VARIANTS` the comparison uses.

**Open questions to settle before writing code, in this order:**

- [x] **How much load do visitors and scrapers put on this.** Measured on
      2026-09-07 by `check_live_load.py`, on the 08:00-09:00 peak. The question
      is what an arriving *client* costs, not what a login costs: a login is
      one argon2 hash and then never again, while a client that sits on the
      map costs something for as long as it is connected.

      The city is small: 386 vehicles on 66 routes at once, 28.5 new GPS fixes
      per second for all of it, a fix per vehicle every 10 s median. The model
      is shared - every client watches the same city - so CPU is per server,
      not per client: one core replays an hour of feed in 12.2 s, or 305x real
      time, which is 197 ms per 60 s epoch, of which 16 ms is the prediction
      itself. Only bytes are per client. A whole-city map frame is 2.6 KiB
      packed (339 vehicles at 8 bytes: 16-bit id, two 16-bit grid offsets, a
      byte of heading, a byte of flags) or 22.3 KiB as JSON, 4.5 KiB gzipped.
      Streamed as deltas at the rate positions actually change, that is
      **228 B/s per client for the entire city** and 28 B/s for a five-route
      set. A hundred clients each watching everything is 23 KB/s, or
      0.18 Mbit/s.

      So a visitor costs bytes and a websocket, not CPU: the model runs once
      whether one person is watching or a thousand. Ordinary visitors are
      therefore free at any plausible number, and nothing here needs a second
      core.

      A scraper is the same arithmetic pointed the wrong way, and that is where
      it stops being free. The expensive thing to build is a city-wide vehicle
      history, and this service hands one over at 228 B/s - cheaper and cleaner
      than polling the upstream feed, because the tracking and the smoothing are
      already done. One scraper is invisible in the numbers; what it takes is a
      copy of the output nobody paid for, continuously. The defence is not
      capacity, it is a gate: an account, which the invite links ration.
- [x] **Authentication or not.** Accounts, decided by the user on 2026-09-07.
      Two reasons, both recorded because neither is a capacity reason: route
      sets that follow a person between phone and laptop cannot live in local
      storage, and an open websocket streaming every vehicle in the city is
      worth more to a scraper than it costs the server to serve. Route sets
      therefore live in Postgres, per account, and the full session-cookie and
      remember-me treatment is in scope as asked. Registration is by admin-minted
      link, following newsense, so the gate is closed by default rather than
      open to anyone who finds the endpoint.
- [x] **Rust or Python.** Python, one service. `newsense` splits by what the
      code needs, and measured against that rule nothing here needs Rust: the
      model is 4700 lines of numpy that would have to be rewritten, and the
      part that might have wanted Rust - the fan-out - moves 228 B/s per
      client and 16 ms of CPU per epoch. A second language buys an IPC hop, a
      second toolchain and two copies of the live state, for a bottleneck that
      does not exist. Revisit only if concurrent clients reach four figures.

**The shape.** One process, because there is only ever one poller: the same
collector that fills `feed.db` today also feeds an in-memory model, and the API
reads that model. Postgres holds accounts and route sets only; the recording
stays in SQLite and the offline replay stays the source of truth about accuracy.

- [x] `commuterlviv/live/` - the service. Written and smoke-tested end to end on
      2026-09-07 against Postgres 17 in podman: 36 assertions over registration,
      login, CSRF, Origin, rate limits, route sets, arrivals and the websocket,
      plus 9 more over remember-me theft and account disabling. All pass.
  - [x] `state.py`: the vehicle feed into live tracks plus the pace model,
        stepped on the same 60 s epoch grid `replay.py` uses. It does not
        reimplement the epoch: `Live.epoch` makes the same four calls
        `replay._flush` makes, in the same order, and `Live.poll_done` reads
        positions through `replay.predictable` and `replay.believed`, so the
        live numbers come from the measured code. Which variant is
        `COMMUTERLVIV_VARIANT` over `config.BY_NAME`, never a client's choice.
  - [x] `wire.py`: the packed frame, 10 bytes a vehicle rather than the 8
        estimated - a `u16` route id was added, because the client colours and
        filters by route and looking it up per vehicle over the websocket was
        the only alternative. Snapshot and delta share one header; removals ride
        along as a list of ids. The delta compares encoded values, not the
        floats behind them: it used to compare raw lat/lon, so a fix that moved
        by less than the half metre a step is worth resent a row the client
        already had, byte for byte.
  - [x] `hub.py`: one websocket per client with its own route filter. No send
        queues: a client diffs the currently published snapshot against what it
        last delivered, so a slow client falls behind in time, not in memory.
        Positions publish per poll (~5 s), arrivals per epoch (60 s).
  - [x] `security.py` + `auth.py`: argon2id passwords, opaque server-side
        sessions in Postgres behind a `__Host-` cookie, remember-me as
        series+token rotated on every use, `hmac.compare_digest` throughout, and
        theft detection - a spent token coming back deletes the series and every
        session that user has. The last two are what `newsense/services/auth`
        does *not* do. One thing the reference also does not need and this does:
        a 30 s grace on the previous token, because two tabs restoring at once
        would otherwise look exactly like theft.
  - [x] CSRF on every unsafe method (double submit: the raw token in a readable
        cookie, its SHA-256 in the session row), an `Origin` check, and token
        buckets that are tight where argon2 is reachable - 20/min per IP and
        5/min per (IP, username) on login and register, against 600/min for the
        rest of the API.
  - [x] `app.py`: session and account endpoints, the catalog behind an ETag,
        route sets CRUD, the timetable view and the websocket. `service.py`
        runs the poll and epoch loops; `db.py` runs forward-only numbered
        migrations at boot; `admin.py` and `commuterlviv admin` mint invite links,
        list accounts and disable one; `commuterlviv serve` runs it.
  - [x] Registration is by admin-minted link, as `newsense` does it: the code
        rides in the path, `POST /api/register/{code}`, mirroring that project's
        `register_with_code` and its `code-register.tsx`. `admin invite` prints
        `<COMMUTERLVIV_WEB_BASE or the first origin>/join/<code>`. Unlike the
        reference, which keeps codes in plaintext, only the SHA-256 is stored
        and the use is spent in the same transaction as the account insert.
  - Recorded deviation: **the live service does not write `feed.db`**. The
        existing collector keeps recording, which costs one extra upstream
        request every five seconds. Giving the recording a second author in the
        middle of the dataset the whole comparison rests on is the one change
        here that could lose data, and the saving is not worth it.
- [x] `web/` - React 19 + Vite 7 + TypeScript + Tailwind 4, the `newsense-web`
      stack minus React Router's framework mode, which buys nothing for a
      single-page map. Vehicles and stops draw on one canvas rather than as DOM
      markers, and positions are interpolated between epochs with
      `requestAnimationFrame`, because "smooth" means the vehicles must move
      between updates rather than jump on them. A route picker, named route
      sets (work, home, ...) with create/edit/delete/select, a stop click
      listing every route through it, and a timetable tab of the next arrival
      per route. Built and driven in headless chromium on 2026-09-07: joining
      through an invite link, signing out and back in, picking routes, vehicles
      arriving over the socket, the canvas changing between frames, a stop click
      opening its card, pinning it into the timetable, and the session surviving
      a reload - all passing, no console errors.
  - [x] Nothing about a vehicle's position passes through React. `live.ts` keeps
        the vehicles in a `Map` the draw loop reads directly, and React
        subscribes through `useSyncExternalStore` to a snapshot of only the
        three things that change rarely: the connection, the arrivals and the
        count. A position frame re-renders nothing.
  - [x] `wire.ts` mirrors `wire.py` and was checked against it rather than by
        eye: a frame encoded in Python decodes byte for byte in node, ids,
        routes, headings, flags and removals exact and lat/lon exact to the
        double. The first version stored coordinates in a `Float32Array` and
        was off by up to 1.5e-6 degrees, a third of the wire's own quantum,
        which is why they are `Float64Array` now.
  - [x] Both end to end checks live in the repo rather than in `/tmp`:
        `check_live.py <code> <code2>` for the service and `check_web.py <code>`
        for the UI, each env-driven, each exiting non-zero on a failure. The
        browser one takes a throwaway profile per run, because a reused one
        carries the last run's session cookie and then the invite link renders
        the map instead of the form.
  - [x] A real map of Lviv under the vehicles: MapLibre GL JS 6.7 - BSD, no
        key, no account - drawing VersaTiles' `shadow` style over OpenStreetMap
        vector tiles, overridable with `VITE_MAP_STYLE`. MapLibre owns the
        gestures and the vehicles keep their own canvas above it, drawn from
        MapLibre's `render` event so the two agree within a frame, with
        `geo.ts` repeating MapLibre's Web Mercator rather than calling
        `map.project` per vehicle per frame. The library and its stylesheet are
        a dynamic import: the sign-in screen still costs 216 kB, 69 kB gzipped,
        and the 1 006 kB of MapLibre arrives only with the map. `check_web.py`
        grew a basemap stage - the tiles are fetched, the city renders under
        the vehicles, and the two projections agree to half a pixel - and all
        sixteen checks pass against the dev server and against `npm run
        preview` on 5174. MapLibre's tile worker is bundled by Vite and handed
        over with `setWorkerUrl`: left to itself it looks for a file the dev
        optimiser mutes and the build never emits, and then draws no city
        while logging nothing. The tile requests are the worker's, which no
        `performance` entry records, so the check attaches to that target over
        CDP and counts them there.
  - Recorded deviation, since **reversed on 2026-09-09**: pinned stops were per
        device, in `localStorage` under `commuterlviv.pins.<username>`, on the
        argument that a pin is not worth carrying between devices and would cost
        a write per tap. Both halves were wrong - people pin the stop they use
        every morning, and the write is one small row - so they went to the
        server; only the map view stays local, under `commuterlviv.view`.

What the references actually are, checked on 2026-09-07 so this does not have to
be rediscovered:

- `newsense` is five services behind one docker-compose: `auth`, `users`,
  `aggregator`, `fetcher` in Rust, `embeddings` in Python. The split is by what
  the code needs, and it is the precedent for putting the model in Python and
  the push layer wherever it belongs.
- `newsense/services/auth` is 1150 lines of axum 0.8: `argon2` for password
  hashing, `tower-sessions` with `tower-sessions-sqlx-store` on Postgres for
  server-side sessions, `axum_csrf` for the CSRF layer, `tower_governor` for
  rate limiting, `axum-extra`'s cookie feature. That is the stack to copy for
  the authenticated case rather than to reinvent.
- `newsense-web` is React 19 with React Router 7 in framework mode, Tailwind 4,
  Vite 7, TypeScript, ~4900 lines of `.tsx`. State is React context
  (`app/lib/auth-context.tsx`, `settings-context.tsx`) over a thin fetch layer
  (`app/lib/api.ts`); components are hand-rolled in `app/components/ui`.

## Phase 8 - a phone app, one-command deployment, and three honesty fixes

Requested 2026-09-07. Phase 7's rule still holds: nothing here may change how a
predictor scores, and the offline replay stays the source of truth.

**Server and web, asked for as "any improvements you have in mind":**

- [x] `GZipMiddleware` on the Starlette app, `minimum_size=1024`. The catalog
      is 219 kB of JSON and went out uncompressed on every first load; it is
      now 30 kB on the wire, measured. The websocket is untouched - it carries
      its own packed bytes and gzip only ever sees whole HTTP responses.
- [x] A locate-me control on the map. `watchPosition`, a dot with an accuracy
      ring drawn from the same canvas as the vehicles, and only the first fix
      moves the camera - after that the dot moves and the view stays where the
      user put it. `metresPerPixel` in `geo.ts` sizes the ring, because a 300 m
      indoor fix drawn as a 6 px dot claims a precision the phone never had.
- [x] A stop search in the header. Prefix matches first, then substring, eight
      hits, each showing which routes call there because a thousand stops
      repeat their names once per direction. Picking one flies the map, selects
      the stop and opens its card.
- [x] A check in `check_web.py` for the search: type, pick the first hit,
      assert the card names that stop. Done, plus a theme check beside it. Two
      hooks were added for it - `data-hit` on a search result and `data-chips`
      on the route chip list - because the old selector was
      `aside section:last-of-type button[title]` and the theme picker became
      the last section. Selecting six routes was also changed to selecting all
      of them: after dark most routes are empty and the vehicle checks failed
      for no reason other than the hour.

**The phone app.** Flutter, chosen by the user on 2026-09-07 over React Native
and a PWA. The binding constraint is F-Droid, which builds from source with no
proprietary SDK in the tree: that rules out Expo, Google Play Services and any
map SDK with a key. Toolchain installed under XDG paths as asked - Flutter
3.47.2 in `~/.local/share/flutter`, Temurin JDK 21 in `~/.local/share/jdk`
(the system JDK is 25, too new for AGP), the Android SDK in
`~/.local/share/android-sdk`, `PUB_CACHE` in `~/.cache/pub`, Gradle in
`~/.local/share/gradle`; `/tmp/flutterenv.sh` exports the lot.

- [x] `mobile/` - the app. `flutter_map` with `vector_map_tiles` because both
      are pure Dart, so the vehicle overlay shares the Flutter frame with the
      basemap exactly as the web overlay shares MapLibre's. Two tabs, Map and
      Times; sheets for routes, sets and the map style; `showSearch` for stops.
      Every vehicle and every stop is one `CustomPaint` driven by a `Ticker`,
      with a `ui.Paragraph` per route cached so text is laid out once rather
      than per vehicle per frame - the Dart analogue of the web's pre-rendered
      badge sprites. `flutter analyze` is clean and the release APK builds.
- [x] A Dart port of the 10-byte wire protocol, checked against `wire.py`.
      `mobile/test/wire_test.dart` decodes a frame `commuterlviv.live.wire.encode`
      actually produced, pasted in as bytes, so it tests agreement between the
      two languages rather than the Dart against itself. 3 tests, all passing.
- [x] Auth needs no server change: the app sends `Origin: app://commuterlviv`,
      which has to be listed in `COMMUTERLVIV_ORIGINS`, and echoes the CSRF cookie
      as `X-CSRF-Token`. `lib/src/api.dart` is a hand-rolled cookie jar over
      `dart:io HttpClient`, matching `lp_csrf` by suffix because the service
      prefixes cookies with `__Host-` when they are secure, and treating an
      empty value or a past expiry as a deletion rather than a value.
- [x] Material 3 on Android, Cupertino on iOS, from one widget tree.
      `PageTransitionsTheme` picks the per-platform page animation, the
      `.adaptive` constructors carry the rest, and `tick()` in `main.dart`
      chooses the platform's haptic.
- [x] F-Droid metadata: fastlane structure under `mobile/fastlane/`, and a
      build recipe at `mobile/fdroid/ua.lviv.commuterlviv.yml`. The release build
      is now unsigned unless `android/key.properties` exists - `flutter create`
      leaves the release signed with the *debug* key, which F-Droid cannot
      take - and `dependenciesInfo` is off, because that blob is Google-signed
      and unreproducible. The licence is MIT, chosen by the user on 2026-09-08
      and now in `LICENSE` at the root; the deployment is `commuterlviv.r1a.nl`,
      which is the app's default server and the recipe's `WebSite`. **One field
      is still a placeholder:** the repository URL, because the project has no
      public repository yet.
- [ ] Locate-me on the phone. **Dropped from v1 deliberately.** The obvious
      package, `geolocator`, pulls `com.google.android.gms:play-services-
      location`, and F-Droid takes no build with a proprietary SDK in it. The
      honest follow-up is a small platform channel over
      `android.location.LocationManager`, which is AOSP, plus `CoreLocation` on
      iOS. Until then the app asks for no location permission at all - the
      Android manifest requests `INTERNET` and nothing else.
- [x] Documented. `mobile/README.md` is the app's own page; the root
      `README.md` gained a "The phone" section beside "The map"; `HANDOFF.md`
      gained the app in its layout tree, in its state of play, in its
      `COMMUTERLVIV_ORIGINS` examples, and a note that `wire.dart` is now a third
      hand-written copy of the frame layout.
- Known caveat: `vector_map_tiles` resolved to `9.0.0-beta.13`, a pre-release.
  Not a choice - it is the version compatible with `flutter_map 8.3.2`.
- [x] Run on a device, asked for by the user on 2026-09-08. An Android 15
      x86_64 emulator (`avd commuterlviv`, pixel_6) with the debug APK built
      `--dart-define=COMMUTERLVIV_BASE=http://10.0.2.2:18099` against the dev
      compose stack. Registered through an invite code, then the map, the route
      sheet, the Times tab and the style sheet, all by `adb shell input`.
      Confirmed: the sign-in screen shows the compiled-in base, the catalog's 72
      routes fill the sheet, the socket carries vehicles that animate between
      frames, the arrow appears only on the ones the server calls moving, and
      the session survives a reinstall.
- Two real bugs came out of that run, both of which only a client could find:
  **a route's `type` is a word** (`bus`, `tram`, `trolleybus`), not the GTFS
  `route_type` number both clients declared. Flutter threw on the cast and
  stopped at a spinner; the web app cast silently and painted every tram and
  trolleybus in the bus hue. Fixed in `models.dart`, `map_theme.dart`,
  `web/src/lib/types.ts` and `web/src/lib/sprites.ts`. And **the map style never
  changed**: `vector_map_tiles` caches the tile images it renders under the
  theme's id, every VersaTiles style parses to the id `default`, so the second
  style read back the first one's pictures from disk - across restarts. Fixed by
  rebuilding the `Style` with `theme: read.theme.copyWith(id: theme.id)`.
- Non-obvious about the emulator, not about this code: the bundled SwiftShader
  renderer segfaults the emulator on Fedora 44, and with `-gpu swangle_indirect`
  the host `gfxstream` GLES2 decoder SIGILLs on Flutter's first frame. The
  combination that works is SwANGLE plus starting the app with
  `--ez enable-software-rendering true --ez enable-impeller false`. In
  `mobile/README.md` and `HANDOFF.md`.
- [x] The server address moved into the menu, asked for by the user on
      2026-09-08. It was only editable from the sign-in screen, which nobody
      already signed in can reach. `lib/src/server_dialog.dart` now holds the
      one dialog both places call; `Api.setBase` reports whether the address
      changed, and a change drops the session, the jar and the cached catalogue
      and returns to sign-in, because all three belonged to the old server.
- [x] **Stops the feed leaves off a route**, reported by the user on 2026-09-08:
      no А16 times at Енергетична (711), with times at the stops either side.
      Investigated first - `stop_times.txt` has no А16 row for stop `44236`, the
      city's own trip updates have 3 404 rows there and none from route 112, and
      `api.lad.lviv.ua/stops/0711` lists only А27 and А53 - so the app agreed
      with the city and the city was wrong. The user knows the stop is served
      and does not want to go upstream, so `commuterlviv/overrides.toml` is read
      at startup and `overrides.py` folds each rule into the pattern before any
      distance is solved. `toward` picks the direction, because the 296°
      platform is not the 116° one and both А16 patterns pass within 12 m.
      `check_overrides.py` rebuilds from scratch and asserts each rule lands.
      Two rules so far, both platforms of the same stop after the user
      confirmed the second: 197 trips call at 711 on shape 37996, 198 at 712 on
      37997 and 38109, and the live service serves А16 arrivals at both.
- [x] **Renamed to CommuterLviv**, asked for by the user on 2026-09-08, who chose
      the deep reading: identifiers as well as branding. `lvivpred/` is
      `commuterlviv/`, `LVIVPRED_*` is `COMMUTERLVIV_*`, the compose project, the
      images and the containers follow, the Dart package is `commuterlviv` and the
      app is `ua.lviv.commuterlviv` - a different application id, so the phone
      takes it as a new app rather than an upgrade. The domain in the defaults and
      the docs is `commuterlviv.r1a.nl`; DNS does not answer for it yet, and the
      deployment addresses this machine by IP, so nothing waits on it. Two things
      kept the old spelling and say why in HANDOFF: the Postgres role and database
      on the existing volume, and the checkout's root directory.
- [x] Map buttons, asked for by the user on 2026-09-08. `lib/src/map_controls.dart`
      is its own file rather than a private widget in `home.dart` so it can be
      driven by a widget test: zoom in and out, disabled at 9 and 18, and a
      compass that appears only once the camera is off north and turns with it.
      The web got only zoom, `NavigationControl` with `showCompass: false`,
      because rotation is deliberately disabled there - the vehicle overlay is a
      second canvas drawn from centre and zoom alone.
- [x] **A pinch turned the map**, reported by the user on 2026-09-08: no
      deadzone, so the twist two fingers always carry rotated the city while
      zooming. `flutter_map` has the thresholds but skips them entirely unless
      `enableMultiFingerGestureRace` is on, which it is not by default, so the
      fix is `mapInteraction` in `lib/src/map_controls.dart`, next to the zoom
      limits and shared with the test: race on, 12° of twist, 0.35 zoom levels
      of spread, and rotation's win set widened to `MultiFingerGesture.all` so
      a deliberate twist does not lock zooming out for the rest of the touch.
      `test/map_gestures_test.dart` drives two pointers through an 8° pinch and
      a 20° twist; it fails with the race off, which is what makes it a test.
      The first threshold tried, 25°, was reported too reluctant the same day
      and halved. Part of why it read as reluctant was the test: at 50 px apart
      the pointers never cleared Flutter's scale slop, so nothing below 25°
      rotated there either. They are 240 px apart now.
- [x] **The phone showed "29814221 min"**, reported by the user on 2026-09-08.
      An arrival's `t` is an absolute unix time, which is what the web's
      `countdown()` has always assumed, and the phone divided it by sixty and
      called it minutes. `lib/src/eta.dart` is now the port of
      `web/src/lib/eta.ts`, thresholds included, and `test/eta_test.dart` pins
      the number that was on the screen. Verified on the emulator against the
      live stack: "now, 2 min, 5 min, 12 min".
- [x] The sign-in screen follows the server's registration mode, noticed by the
      user on 2026-09-08: `COMMUTERLVIV_REGISTRATION=open` was reachable by neither
      client, because both only ever posted `/api/register/{code}` and the web
      form only appeared behind an invite link. `/api/health` now also reports
      `registration`, which is the only endpoint a client can read before anyone
      is signed in and is no secret anyway. Both clients ask on load and show
      what it allows - an invite field under `code`, a sign-up button under
      `open`, neither under `closed` - and post the codeless `/api/register`
      when there is no code. Verified against the running stack: `code` refuses
      it with "that invite code is not valid", `open` gets as far as checking
      the password.
- [x] Password managers, after Bitwarden would not fill the form on the user's
      phone on 2026-09-08. A Flutter form is one native view, so the manager
      sees nothing to fill unless the app says what the fields are: the two are
      now in an `AutofillGroup` with `AutofillHints.username` and
      `password` - `newPassword` while joining - and `_submit` calls
      `TextInput.finishAutofillContext()`, which is what prompts the manager to
      save, since the form never leaves the screen on its own. The web form was
      already fine - a real `<form>` with `autocomplete` on both fields - and
      gained `name="username"` and `name="password"` for the older heuristics.
      `mobile/lib` and `mobile/test` are now `dart format` clean throughout,
      which touched nine files.
- [x] A debug APK for the user's own phone, built
      `--dart-define=COMMUTERLVIV_BASE=http://10.8.0.2:8080` and handed over from a
      `python3 -m http.server 8099` bound to the VPN address. Debug and not
      release for two reasons: the release manifest forbids cleartext, and the
      deployment has no certificate; and a release APK is unsigned without
      `android/key.properties`.

**Deployment, asked for on 2026-09-07 with `newsense` as the example.** Today
`docker-compose.yml` starts Postgres and nothing else; the service and the web
build are run by hand.

- [x] `deploy/service.Dockerfile` and `deploy/web.Dockerfile`, and
      `docker-compose.yml` bringing up four containers - db, service, collector,
      and Caddy in front - on `docker compose up -d --build`. Caddy serves the
      built UI, proxies `/api` and `/ws` to the service and falls back to
      `index.html`, so the whole thing is one origin and the `__Host-` cookies
      need no cross-origin rules. The collector is in the stack rather than
      beside it because `service.warm` replays the last two hours of its
      recording at boot, and without a local recording every restart is twenty
      minutes of cold predictions. Verified end to end under a scratch project:
      health through Caddy, the SPA fallback, a gzipped catalog at 29.7 kB,
      `admin invite`, registration, and a websocket carrying `hello` and a
      snapshot frame.
- [x] `docker-compose.dev.yml`, an overlay: source mounted, Vite's dev server in
      place of the built files (`build: !reset null`), `COMMUTERLVIV_DEV=true`, and
      the db, service and pgadmin ports open. The service is restarted rather
      than reloaded on a source change - it holds a warmed model that a reloader
      would discard on every keystroke. Verified on shifted ports, since this
      machine already has all four in use: Vite serving with its HMR client,
      `/api/health` through Vite's proxy, and the service answering directly on
      8099 as the phone app needs.
- [x] `docker-compose.tls.yml`, a second overlay for when the machine is the one
      the domain points at: Caddy takes 80/443 and gets its own certificate.
      `COMMUTERLVIV_SITE_ADDRESS` is required there, with a compose `:?` message
      rather than a silent fallback to `:8080`.
- [x] `.env.example` with every setting and its default, `.dockerignore` so the
      0.95 GB `data/` never enters a build context, and two guides in
      `README.md` - production and development - each a `cp`, a `docker compose`
      and an `admin invite`.
- Non-obvious, and the one real bug found while testing: **`try_files` runs in
  an earlier Caddy phase than `reverse_proxy`**, so a single block containing
  both rewrote `/api/health` to `/index.html` before the proxy matcher ever saw
  the path - the API answered with the app's HTML and a 200. The two halves have
  to be exclusive `handle` blocks. Recorded in `deploy/Caddyfile` beside the
  code.
- Note: the compose project is now pinned to `commuterlviv`, so an older checkout
  that ran the previous file from `main/` has its database left behind in the
  `main_postgres_data` volume.

**Three honesty fixes to the map, all reported by the user on 2026-09-07:**

- [x] **The heading arrows point the wrong way.** Root cause: `_heading` in
      `live/state.py` preferred the feed's reported bearing and only fell back
      to the route. The reported bearing is now gone from the codebase - out of
      `state.fix`, out of `service.py`, out of the pruning in `epoch` - and the
      arrow is the tangent of the vehicle's own shape at `s`, averaged over
      `HEAD_SPAN = 25 m` either side so one bent segment cannot swing it. This
      is right by construction: `s` grows in the direction of travel, and it is
      the same geometry the arrival times are computed along, so the arrow and
      the times can no longer disagree. The arrow was hidden entirely on a
      vehicle that is not moving; see the amendment at the end of this list.
- [x] **Be conservative about motion.** The tracker already carries the
      variance of its own speed estimate, so the test is evidence rather than a
      new constant: `tr.v - SURE * sqrt(tr.P[1,1]) > track.HOLD_SPEED` with
      `SURE = 1.0`. That answer rides the wire as flag bit 1 (`MOVING`), the
      marker of a vehicle that fails it sits at its last known place, and one
      that passes is dead-reckoned only `DAMP = 0.7` of the distance. Drawn
      short of where it is, a vehicle reads as caution; drawn past a stop it
      has not reached, it reads as a lie. `replay.believed` is untouched, so
      the timetable shows exactly the numbers the offline comparison measured.
- [x] **A map theme switcher.** `web/src/lib/theme.ts` holds the five
      VersaTiles styles, the `localStorage` choice and `ink(dark)`, the overlay
      palette. The palette had to move there too: the near-white nub reads on
      `shadow` and vanishes on `neutrino`. Switching is `map.setStyle`, so the
      camera, the gestures and the overlay all survive it.
- [x] **Pinned stops moved to the server, and to feed ids**, 2026-09-09. Each
      client kept its own pins in its own storage, as catalog positions, so the
      phone and the browser disagreed about what was pinned and a stop added to
      the feed shifted every pin after it onto its neighbour. They live in
      `user_prefs.data` now, behind `GET`/`POST /api/pins`, validated against
      the catalog on the way in, unknown ids dropped rather than the write
      refused, capped at 63 - one below the 64 stops a socket may watch, so the
      pins plus whichever card is open always fit. Each client migrates its own
      old key once and drops it only after the upload lands. Verified against
      the running stack.
- [x] **The websocket re-checks its session**, 2026-09-09. It was authenticated
      at the handshake and never again, so signing out somewhere else left the
      socket fed until the tab closed. `app.py`'s `expire` asks every 60 s with
      `touch=False` - `load_session` refreshes the idle clock otherwise - and
      closes 4401. Verified: logout, closed after 60 s, code 4401.
- [x] **A client's own message stopped waking every other client**, 2026-09-09.
      `publish` woke one shared event, so a hundred idle clients recomputed
      their diffs whenever any one of them changed a filter. Each client has its
      own `asyncio.Event` now; the sequence counter still does the race
      protection.
- [x] **A rate limit on the socket**, asked for by the user on 2026-09-09.
      Five messages a second sustained, burst 60, close 1008 after 500 refusals,
      and `ws_max_size` at 16 KB so a large frame is refused at the protocol
      rather than read into memory. Generous by an order of magnitude against a
      person changing routes as fast as a person can; it is there for the client
      that loops. Verified: 2000 messages, closed with 1008.
- [x] **The phone keeps its basemap between runs**, asked for by the user on
      2026-09-09. `vector_map_tiles` was caching under the temporary directory,
      which Android empties at will. `lib/src/map_tiles.dart` puts it under
      application support - 200 MB, 90 days, 32 MB and 50 tiles in memory.
- [x] **The web app puts its state in the address bar**, 2026-09-09.
      `web/src/lib/url.ts` reads and writes `routes`, `stop` and `tab` as feed
      ids, once at mount and on every change through `history.replaceState`, so
      a link carries what is on the screen. A link that names routes wins over
      the account's active set; one that names a stop flies there.
- [x] **The web app says what went wrong**, 2026-09-09. Every failed call went
      into a console nobody had open, leaving the splash reading "…". A 401 puts
      the sign-in screen up; anything else is a retryable splash before there is
      a screen, and a dismissible banner after.
- [x] **Stops near me**, 2026-09-09. `metres()` in `web/src/lib/geo.ts` and a ◎
      button in the search box: `navigator.geolocation`, the stops within 2 km,
      nearest first, with the distance where the route list goes.
- [x] **`home.dart` split into the widgets it was hiding**, 2026-09-09. It was
      896 lines and every widget in it took a `_HomeScreenState` back-pointer,
      which works only because Dart privacy is per library. The tabs, the card,
      the sheets and the search are their own files now, each taking what it
      draws and calling back.
- [x] **Ukrainian**, 2026-09-09. `web/src/lib/i18n.ts` and
      `mobile/lib/src/strings.dart` hold the two dictionaries, key for key, so
      the clients say the same things. The language is the stored choice, else
      Ukrainian for a browser or phone asking for it, and it is read once per
      load: changing it reloads the page or asks for a restart, which buys not
      threading a provider through every widget. `intl` and ARB files were
      considered and dropped - two locales and sixty strings do not pay for a
      code generator. Server error messages are still English: they come from
      `live/app.py` and are shown as sent.
- [x] **The web app installs**, 2026-09-09. `web/public/manifest.webmanifest`
      and `web/public/sw.js`: an icon, a standalone window, and a shell that
      opens offline. The worker caches what it has served rather than a
      generated precache list - vite hashes asset names - and never `/api` or
      `/ws`. Offline it opens and says the service is not answering, which is
      the truth. Verified against the live stack: the manifest, the worker and
      the icons are served, and `/sw.js` carries `Cache-Control: no-cache`.
- [x] **One command that checks the checkout**, 2026-09-09. `check.sh`: ruff's
      will-it-run rules, the package imports, the web types and build, and
      `flutter analyze`/`flutter test`. Deliberately nothing that needs a
      database, a service or a recording - `check_live.py`, `check_web.py` and
      `check_parallel.py` each do, and a check that cannot be run is a check
      that gets skipped. A GitHub Actions workflow is the obvious next step and
      is not written: there is no remote to run it on, so it could not be
      exercised, and an untested workflow is worse than none.
- [x] **A standing vehicle shows its direction too**, asked for by the user on
      2026-09-09. Hiding the wedge unless `MOVING` left no way to tell one end
      of a route from the other at exactly the moment somebody is looking - a
      marker at a stop is the common case, not the rare one. The wedge is drawn
      always now: solid when the vehicle is under way, an outline when it
      stands. The heading is the route's tangent at `s` either way, so nothing
      is claimed that was not already known; only the fill says whether it is
      being acted on. Both clients, and the wedge follows the stale marker's
      opacity now rather than staying at full.

## Deliverables

- `reports/approaches.md` regenerated with every scored variant, keeping the
  existing paired-on-common-support method and bootstrap intervals
- `reports/sweeps.json` with the hyperparameter grids
- `reports/residual.md` and `reports/residual-midday.md`, the two splits of
  Phase 4, each with its `.json` alongside
- `reports/stack.md` and `reports/stack-midday.md`, the same two splits of
  Phase 5, each with its `.json` alongside, and each printing the members'
  error correlation next to the result
- a section in `reports/findings.md` for whatever the new results contradict
- this file, kept current: mark each item as it lands, and keep the reason when
  something is dropped
