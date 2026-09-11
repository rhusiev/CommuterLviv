# Blending the predictors

Weights fitted on the 4304837 predictions emitted from 09-07 06:08 to 09-07 23:44, and everything scored on the 4534604 emitted from 09-08 05:30 to 09-08 23:48, covering 185682 crossings. Members and blends answer the identical rows, so the interval is on the difference from `full` rather than on either MAE.

| predictor | MAE s | vs full | 95% CI on the difference | median s | bias s | <60 s |
|---|---|---|---|---|---|---|
| stack-robust | 128.1 | -10.3% | -15.7 .. -13.8 | 74 | -13 | 43.7% |
| stack | 128.9 | -9.8% | -15.1 .. -12.9 | 76 | -2 | 43.0% |
| debias | 138.4 | -3.2% | -5.1 .. -3.9 | 81 | -11 | 41.1% |
| full | 142.9 | +0.0% | - | 83 | -42 | 40.7% |
| stack-median | 143.2 | +0.2% | -0.3 .. +0.9 | 82 | -62 | 40.8% |
| no-prior | 145.5 | +1.8% | - | 83 | -81 | 40.8% |
| sections | 151.9 | +6.3% | - | 89 | -75 | 38.8% |
| api | 2640.0 | +1747.4% | - | 172 | -2344 | 23.7% |

## By horizon, MAE in seconds

| predictor | 0-1 | 1-2 | 2-5 | 5-10 | 10-20 | 20-45 |
|---|---|---|---|---|---|---|
| stack-robust | 16 | 27 | 44 | 74 | 123 | 212 |
| stack | 16 | 27 | 44 | 74 | 123 | 213 |
| debias | 18 | 30 | 48 | 81 | 135 | 225 |
| full | 18 | 30 | 49 | 81 | 135 | 238 |
| stack-median | 18 | 29 | 47 | 79 | 132 | 243 |
| no-prior | 16 | 27 | 44 | 75 | 131 | 254 |
| sections | 20 | 32 | 50 | 83 | 138 | 260 |
| api | 1082 | 1079 | 1077 | 1092 | 1380 | 5292 |

## How alike the members are, on the test window

A blend can only win where the errors disagree. Correlations near one mean the members are making the same mistake and there is nothing to average away.

| | full | no-prior | sections | api |
|---|---|---|---|---|
| full | 1.00 | 0.92 | 0.96 | 0.02 |
| no-prior | 0.92 | 1.00 | 0.91 | 0.05 |
| sections | 0.96 | 0.91 | 1.00 | 0.02 |
| api | 0.02 | 0.05 | 0.02 | 1.00 |

## The weights `stack-robust` fitted

| horizon | full | no-prior | sections | api | intercept s |
|---|---|---|---|---|---|
| 0-1 min | -0.48 | +1.57 | -0.09 | +0.00 | +0 |
| 1-2 min | -0.13 | +1.15 | -0.03 | +0.00 | +1 |
| 2-5 min | -0.04 | +0.98 | +0.06 | -0.00 | +5 |
| 5-10 min | +0.01 | +0.90 | +0.09 | -0.00 | +17 |
| 10-20 min | -0.01 | +0.81 | +0.20 | +0.00 | +48 |
| 20-45 min | +0.09 | +0.75 | +0.16 | +0.00 | +144 |

## The weights `stack` fitted

| horizon | full | no-prior | sections | api | intercept s |
|---|---|---|---|---|---|
| 0-1 min | -0.55 | +1.40 | +0.15 | +0.00 | -2 |
| 1-2 min | -0.20 | +1.00 | +0.20 | +0.00 | -3 |
| 2-5 min | -0.13 | +0.84 | +0.28 | -0.00 | +1 |
| 5-10 min | -0.10 | +0.78 | +0.32 | -0.00 | +16 |
| 10-20 min | -0.16 | +0.73 | +0.42 | +0.00 | +57 |
| 20-45 min | -0.06 | +0.75 | +0.31 | +0.00 | +185 |

## The weights `debias` fitted

| horizon | full | no-prior | sections | api | intercept s |
|---|---|---|---|---|---|
| 0-1 min | +1.00 | +0.00 | +0.00 | +0.00 | -3 |
| 1-2 min | +1.00 | +0.00 | +0.00 | +0.00 | -5 |
| 2-5 min | +1.00 | +0.00 | +0.00 | +0.00 | -6 |
| 5-10 min | +1.00 | +0.00 | +0.00 | +0.00 | -3 |
| 10-20 min | +1.00 | +0.00 | +0.00 | +0.00 | +11 |
| 20-45 min | +1.00 | +0.00 | +0.00 | +0.00 | +82 |
