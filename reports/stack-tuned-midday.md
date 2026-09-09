# Blending the predictors

Weights fitted on the 1153738 predictions emitted from 09-05 20:58 to 09-06 11:59, and everything scored on the 1363166 emitted from 09-06 12:00 to 09-06 18:56, covering 62444 crossings. Members and blends answer the identical rows, so the interval is on the difference from `full` rather than on either MAE.

| predictor | MAE s | vs full | 95% CI on the difference | median s | bias s | <60 s |
|---|---|---|---|---|---|---|
| stack-robust | 93.9 | -14.4% | -17.4 .. -14.4 | 54 | -35 | 53.2% |
| stack | 94.3 | -14.0% | -17.1 .. -13.7 | 56 | -24 | 52.4% |
| full+quantile | 100.6 | -8.3% | -11.1 .. -7.3 | 59 | +0 | 50.3% |
| stack-median | 106.6 | -2.8% | -4.4 .. -1.9 | 60 | -52 | 49.7% |
| no-prior | 108.8 | -0.9% | - | 63 | -63 | 48.7% |
| full | 109.7 | +0.0% | - | 64 | -19 | 48.1% |
| debias | 110.0 | +0.3% | +0.2 .. +0.5 | 65 | -28 | 47.5% |
| tuned | 115.2 | +5.1% | - | 64 | -84 | 47.9% |
| sections | 116.3 | +6.0% | - | 67 | -56 | 46.6% |
| api | 679.1 | +519.2% | - | 145 | -351 | 27.5% |

## By horizon, MAE in seconds

| predictor | 0-1 | 1-2 | 2-5 | 5-10 | 10-20 | 20-45 |
|---|---|---|---|---|---|---|
| stack-robust | 14 | 23 | 36 | 59 | 95 | 163 |
| stack | 15 | 24 | 37 | 60 | 95 | 163 |
| full+quantile | 18 | 28 | 44 | 68 | 103 | 167 |
| stack-median | 16 | 25 | 39 | 64 | 104 | 192 |
| no-prior | 16 | 25 | 38 | 63 | 106 | 198 |
| full | 17 | 28 | 43 | 70 | 112 | 188 |
| debias | 17 | 28 | 44 | 71 | 114 | 187 |
| tuned | 15 | 24 | 37 | 62 | 108 | 219 |
| sections | 19 | 30 | 44 | 71 | 114 | 207 |
| api | 527 | 541 | 561 | 602 | 671 | 832 |

## How alike the members are, on the test window

A blend can only win where the errors disagree. Correlations near one mean the members are making the same mistake and there is nothing to average away.

| | full | no-prior | sections | tuned | api |
|---|---|---|---|---|---|
| full | 1.00 | 0.89 | 0.94 | 0.91 | 0.07 |
| no-prior | 0.89 | 1.00 | 0.88 | 0.94 | 0.03 |
| sections | 0.94 | 0.88 | 1.00 | 0.93 | 0.10 |
| tuned | 0.91 | 0.94 | 0.93 | 1.00 | 0.07 |
| api | 0.07 | 0.03 | 0.10 | 0.07 | 1.00 |

## The weights `stack-robust` fitted

| horizon | full | no-prior | sections | tuned | api | intercept s |
|---|---|---|---|---|---|---|
| 0-1 min | -0.69 | +0.43 | +0.04 | +1.22 | -0.00 | +1 |
| 1-2 min | -0.40 | +0.39 | +0.10 | +0.92 | -0.00 | +2 |
| 2-5 min | -0.35 | +0.34 | +0.16 | +0.85 | -0.00 | +7 |
| 5-10 min | -0.36 | +0.29 | +0.19 | +0.88 | -0.00 | +21 |
| 10-20 min | -0.43 | +0.31 | +0.25 | +0.88 | -0.00 | +54 |
| 20-45 min | -0.47 | +0.39 | +0.32 | +0.77 | -0.00 | +143 |

## The weights `stack` fitted

| horizon | full | no-prior | sections | tuned | api | intercept s |
|---|---|---|---|---|---|---|
| 0-1 min | -0.92 | +0.27 | +0.28 | +1.36 | +0.00 | -1 |
| 1-2 min | -0.54 | +0.37 | +0.26 | +0.92 | -0.00 | -0 |
| 2-5 min | -0.46 | +0.39 | +0.33 | +0.74 | -0.00 | +4 |
| 5-10 min | -0.46 | +0.32 | +0.34 | +0.81 | -0.00 | +20 |
| 10-20 min | -0.57 | +0.30 | +0.36 | +0.91 | +0.00 | +65 |
| 20-45 min | -0.83 | +0.36 | +0.45 | +1.01 | +0.01 | +221 |

## The weights `debias` fitted

| horizon | full | no-prior | sections | tuned | api | intercept s |
|---|---|---|---|---|---|---|
| 0-1 min | +1.00 | +0.00 | +0.00 | +0.00 | +0.00 | -3 |
| 1-2 min | +1.00 | +0.00 | +0.00 | +0.00 | +0.00 | -8 |
| 2-5 min | +1.00 | +0.00 | +0.00 | +0.00 | +0.00 | -11 |
| 5-10 min | +1.00 | +0.00 | +0.00 | +0.00 | +0.00 | -16 |
| 10-20 min | +1.00 | +0.00 | +0.00 | +0.00 | +0.00 | -20 |
| 20-45 min | +1.00 | +0.00 | +0.00 | +0.00 | +0.00 | +8 |
