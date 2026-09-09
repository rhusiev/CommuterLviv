# Blending the predictors

Weights fitted on the 1153773 predictions emitted from 09-05 20:58 to 09-06 11:59, and everything scored on the 1363179 emitted from 09-06 12:00 to 09-06 18:56, covering 62444 crossings. Members and blends answer the identical rows, so the interval is on the difference from `full` rather than on either MAE.

| predictor | MAE s | vs full | 95% CI on the difference | median s | bias s | <60 s |
|---|---|---|---|---|---|---|
| stack-robust | 95.2 | -13.2% | -15.7 .. -13.2 | 55 | -17 | 52.8% |
| stack | 97.2 | -11.4% | -14.0 .. -11.0 | 57 | -7 | 51.7% |
| full+quantile | 100.6 | -8.3% | -11.1 .. -7.3 | 59 | +0 | 50.3% |
| stack-median | 107.0 | -2.4% | -3.8 .. -1.7 | 61 | -40 | 49.2% |
| no-prior | 108.8 | -0.9% | - | 63 | -63 | 48.7% |
| full | 109.7 | +0.0% | - | 64 | -19 | 48.1% |
| debias | 110.0 | +0.3% | +0.2 .. +0.5 | 65 | -28 | 47.5% |
| sections | 116.3 | +6.0% | - | 67 | -56 | 46.6% |
| api | 679.1 | +519.1% | - | 145 | -351 | 27.5% |

## By horizon, MAE in seconds

| predictor | 0-1 | 1-2 | 2-5 | 5-10 | 10-20 | 20-45 |
|---|---|---|---|---|---|---|
| stack-robust | 15 | 25 | 38 | 61 | 97 | 163 |
| stack | 16 | 25 | 39 | 62 | 98 | 167 |
| full+quantile | 18 | 28 | 44 | 68 | 103 | 167 |
| stack-median | 17 | 27 | 41 | 67 | 107 | 188 |
| no-prior | 16 | 25 | 38 | 63 | 106 | 198 |
| full | 17 | 28 | 43 | 70 | 112 | 188 |
| debias | 17 | 28 | 44 | 71 | 114 | 187 |
| sections | 19 | 30 | 44 | 71 | 114 | 207 |
| api | 527 | 541 | 561 | 602 | 671 | 832 |

## How alike the members are, on the test window

A blend can only win where the errors disagree. Correlations near one mean the members are making the same mistake and there is nothing to average away.

| | full | no-prior | sections | api |
|---|---|---|---|---|
| full | 1.00 | 0.89 | 0.94 | 0.07 |
| no-prior | 0.89 | 1.00 | 0.88 | 0.03 |
| sections | 0.94 | 0.88 | 1.00 | 0.10 |
| api | 0.07 | 0.03 | 0.10 | 1.00 |

## The weights `stack-robust` fitted

| horizon | full | no-prior | sections | api | intercept s |
|---|---|---|---|---|---|
| 0-1 min | -0.33 | +1.37 | -0.04 | +0.00 | +1 |
| 1-2 min | -0.12 | +1.02 | +0.10 | +0.00 | +0 |
| 2-5 min | -0.09 | +0.88 | +0.21 | +0.00 | +4 |
| 5-10 min | -0.08 | +0.79 | +0.29 | -0.00 | +14 |
| 10-20 min | -0.13 | +0.75 | +0.38 | +0.00 | +41 |
| 20-45 min | -0.22 | +0.73 | +0.49 | +0.01 | +122 |

## The weights `stack` fitted

| horizon | full | no-prior | sections | api | intercept s |
|---|---|---|---|---|---|
| 0-1 min | -0.46 | +1.17 | +0.29 | +0.00 | -2 |
| 1-2 min | -0.20 | +0.91 | +0.30 | -0.00 | -3 |
| 2-5 min | -0.19 | +0.79 | +0.40 | -0.00 | -0 |
| 5-10 min | -0.18 | +0.73 | +0.45 | -0.00 | +10 |
| 10-20 min | -0.26 | +0.73 | +0.52 | +0.00 | +46 |
| 20-45 min | -0.47 | +0.79 | +0.67 | +0.01 | +185 |

## The weights `debias` fitted

| horizon | full | no-prior | sections | api | intercept s |
|---|---|---|---|---|---|
| 0-1 min | +1.00 | +0.00 | +0.00 | +0.00 | -3 |
| 1-2 min | +1.00 | +0.00 | +0.00 | +0.00 | -8 |
| 2-5 min | +1.00 | +0.00 | +0.00 | +0.00 | -11 |
| 5-10 min | +1.00 | +0.00 | +0.00 | +0.00 | -16 |
| 10-20 min | +1.00 | +0.00 | +0.00 | +0.00 | -20 |
| 20-45 min | +1.00 | +0.00 | +0.00 | +0.00 | +7 |
