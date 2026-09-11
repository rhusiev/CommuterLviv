# What this branch is

`main` is the product: the server, the web app and the phone app, and nothing
else. This branch is everything that produced it and is not needed to run it -
the measurement project, its results, and the notes on the city's feeds. It is
frozen at the last commit before `main` was reduced to production, and it is
where to come back to before changing how prediction works.

Nothing here is imported by the shipped service. It is kept because the numbers
cost six days of recording and a few hundred CPU-hours of replay, and they
cannot be re-derived from `main`.

## Read in this order

| Read | For |
|---|---|
| `HANDOFF.md` | what state the work was in, which document answers which question |
| `PLAN.md` | the approach comparison phase by phase, every item with its status |
| `reports/findings.md` | what the numbers turned out to mean - fifteen findings, each with its measurement |
| `reports/approaches.md` | the scoreboard: every switchable approach on one recording |
| `reports/crossday.md` | the same, cut by service day, which is what settled the shipped model |
| `docs/` | the city's own APIs: endpoints, fields and traps, verified against the live feeds |

## The results that decided what ships

`profile` is the served model - an hour-of-day pace profile per cell with a
week-long half-life. It won every service day and every weekday in the 21-variant
cross-day run: 134.3 s MAE pooled against `full`'s 138.2 over 15 454 758 paired
predictions, p60 0.440 against 0.420. `reports/findings.md` finding 14 has the
table and the caveats - notably that the per-day intervals are each variant's own
bootstrap rather than an interval on the difference.

Two earlier conclusions were reversed by the longer recording and the reversal is
the point: `tuned` and `slow-day` both led on a single day and both lose on the
full one. A constant fitted on one day was fitted to that day.

One thing was never explained and is worth picking up: the `api` predictor scores
1987 s and 2476 s on 8 and 9 September against 558 s on the 7th. That looks like
operator feed outages rather than prediction quality, and no number from those two
days should be quoted until someone checks.

## The code that is here and not on `main`

`commuterlviv/` on this branch still has the measurement half: `replay` with its
parallel `run_many`, `score`, `evaluate`, `experiments`, `sweep`, `crossday`,
`features`, `residual`, `stack`, `merge`, `truth`, `predictors`, `diag` and
`check`, plus the `check_*.py` end-to-end scripts and the `data/feed.db` recording
format they all read. `commuterlviv/cli.py` here exposes fifteen commands; on
`main` it exposes the five that serve.

The recording itself is not in git - it is about a gigabyte - and lives in `data/`
on the machine that collected it.
