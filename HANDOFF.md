# Start here

This repo measures how well bus arrival times in Lviv can be predicted, and how
much each part of a predictor is worth. It is a measurement project, not a
product: nothing here is deployed except the collector, which records the city's
live feeds so everything else can be replayed against them offline.

## Read in this order

| Read | For |
|---|---|
| this file | what state the work is in and what to do next |
| [docs/README.md](docs/README.md) | the city's APIs - endpoints, fields, traps. Six files, all verified against the live feeds on 2026-09-05 |
| [README.md](README.md) | how our predictor works, in eight steps from a GPS fix to an ETA; also how to run the collector and on a VPS |
| [PLAN.md](PLAN.md) | the approach comparison, phase by phase, with every item's status. **Reread it after every compaction** |
| [reports/findings.md](reports/findings.md) | what the numbers turned out to mean. Seven findings, each with the measurement behind it |
| [reports/approaches.md](reports/approaches.md) | the current scoreboard |

Everything else is derived: `reports/approaches.json` and `reports/sweeps.json`
are machine-readable copies of the two report tables.

## The one-paragraph version

The city publishes GTFS static and GTFS-Realtime at
`https://track.ua-gis.com/gtfs/lviv/` with no key and no rate limit, plus an
undocumented arrivals-board JSON API at `api.lad.lviv.ua/stops/<code>`. A
collector records all three into `data/feed.db`. A replay walks that recording
forwards in time, map-matching every vehicle onto its trip's shape, learning how
long each 100 m of road is taking right now, and emitting an ETA for every stop
ahead of every vehicle once a minute. Because the recording also says when each
vehicle *actually* passed each stop, every predictor - ours, the official
`trip_updates` feed, the arrivals board, and the bare timetable - can be scored
on exactly the same events. Ours is currently about twice as accurate as the
official feed, and the interesting question is no longer whether it works but
which of its parts are carrying it.

## State of play, 2026-09-06

- **The collector is running on this machine** (`pgrep -af "lvivpred collect"`,
  pid 32550). `data/feed.db` is 0.79 GB and holds 2026-09-05 20:17 to now.
  Leave it running: Phase 6 is blocked until it covers three weekdays.
- **Phases 0-3 are done and scored.** `tuned` leads at 114 s MAE, `full` (the
  shipped model) is at 120 s, the official API is far behind. See `PLAN.md`.
- **Phase 4 is in progress.** Its first item - dumping one feature row per
  emitted prediction - has just landed and is described below. Nothing has been
  fitted on those features yet. That is the next thing to do.
- **Phases 5 and 6 are untouched.** Phase 6 is blocked on data, not on work.

## What just landed, and what it enables

`lvivpred/features.py` plus a hook in `replay.py` write one row per emitted
prediction, with fourteen columns, all of them causally available at the moment
the prediction was made. Rows are appended in the same loop and under the same
mask as the predictions themselves, so feature row *i* is prediction row *i* and
the join to the ground truth is by position, never by a key -
`predictors.event_of` supplies the crossing id for each row.

```sh
python3 -m lvivpred features --out reports/feats.npz            # whole recording
python3 -m lvivpred features --out /tmp/f.npz \
    --from 2026-09-06T07:00 --to 2026-09-06T07:20                # a smoke test
```

A 20-minute window gives about 18 000 rows; the command prints the exact count
for whatever window you ask for, and collecting the features costs about a
quarter of the replay's time. `features.load(path)` returns `(X, y, w, at, event, cols)` where
`y` is the log ratio the plan specifies and `w` is the inverse-gap weight.

Three supporting refactors went with it, none of which change any score:
`predictors.event_of` (extracted so features could reuse the row-to-crossing
mapping), `model.integrate` (generalised from `time_between`, so the same
partly-crossed-cell arithmetic serves the evidence-weight integrals), and the
`feats=` argument on `replay.run`. `check_parallel.py` confirms the replay still
produces a byte-identical fingerprint sequentially and in parallel.

## Do this next

1. **Fit the residual models** - `PLAN.md` Phase 4 lists five, in order:
   `resid-const` (per horizon bucket, not pooled - the reason is in the plan),
   `resid-linear`, `resid-gbm`, `resid-quantile`, `resid-mlp`. Then a feature
   ablation on whichever wins. The features are already dumped; this is fitting
   and scoring only.
2. **Then Phase 5**, the stacks - the plan argues this is the likeliest single
   win left, because the predictors fail differently at different horizons.
3. **Geometry sweeps last** (`CELL` at 50/100/200/400 m, `CORRIDOR_GRID` at
   60/120/250 m and 4/8/16 octants). They are last because each value costs a
   network rebuild, not because they matter least.

Two deviations from the plan's Phase 4 spec, already made:

- The plan lists `horizon` and `model_eta` as separate features. They are the
  same quantity - the predicted seconds to arrival - so only one is recorded.
- `fix_age` was added beyond the plan's list: how stale the believed position is
  when the prediction is made. It is causally available and obviously relevant.

The plan's split (fit on the evening, score on the morning) can now be widened:
it was written when the recording ended at 09:32 and there are six more hours.
Fit on rows emitted before 2026-09-06 00:00, drop the first 30-40 minutes where
the model is cold, and test from 05:30 to the end. One replay, not two, with
rows split by emit time - still causal, and the model state at 05:30 then
carries the evening's learning as it would in deployment.

## Things that will cost you an hour if nobody tells you

- **MAE numbers are only comparable within one run.** Each run scores on the
  crossings every variant answered, and that support changes with the window and
  with the variant list. Five different supports exist in the reports already,
  from 80 572 to 94 376 crossings. Never compare a number across two runs;
  rerun both variants together instead.
- **`scikit-learn` 1.9.0 is installed** in the user site, and numpy 2.4.6 and
  pandas 2.3.3. There is no scipy and no torch. Keep sklearn an **optional
  extra and out of `requirements.txt`** - the collector runs on a small VPS and
  its footprint should not change.
- **The subcommand is `experiment`, singular.** `python3 -m lvivpred` with no
  arguments prints all seven.
- **There is no `sqlite3` command line tool** on this machine. Query the
  recording with `python3 -c` and the `sqlite3` module.
- **The city runs no service between roughly 00:00 and 05:30**, because of the
  war. A replay window inside that gap is empty by construction, and `replay.run`
  raises `NoData` saying so rather than failing obscurely.
- **Run `python3 check_parallel.py` after anything that touches `replay.py`.**
  It asserts the sequential and parallel replays track the same crossings in the
  same order. It takes about a minute.
- **The shell is zsh.** `grep --include=*.py` and unquoted `===MARKER===` both
  fail under it.

## Layout

```
lvivpred/
  collect.py    poll the three feeds into data/feed.db, forever
  network.py    static GTFS -> shapes, stops, trips, patterns
  track.py      map-matching and the per-vehicle Kalman filter
  model.py      the estimator: cells, corridors, two half-lives, shrinkage
  baselines.py  the estimators that replace it: table, knn, median
  config.py     every approach, as a set of switches on one dataclass
  replay.py     walk the recording forwards, emit ETAs, collect features
  features.py   one feature row per emitted prediction
  truth.py      when each vehicle actually passed each stop
  predictors.py the four predictors reduced to one common form
  score.py      paired scoring on common support, with bootstrap intervals
  experiments.py / sweep.py / check.py / diag.py / evaluate.py / cli.py
check_parallel.py  the replay-identity guard described above
check_prior.py     a one-off: is `tuned` just `no-prior` by another route
deploy/            a systemd unit for the collector
data/              the recording and the learned model; gitignored, rebuildable
```
