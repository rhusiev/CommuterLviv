# Blending the predictors

Weights fitted on the 4302904 predictions emitted from 09-07 06:08 to 09-07 23:44, and everything scored on the 4531654 emitted from 09-08 05:30 to 09-08 23:48, covering 185682 crossings. Members and blends answer the identical rows, so the interval is on the difference from `full` rather than on either MAE.

| predictor | MAE s | vs full | 95% CI on the difference | median s | bias s | <60 s |
|---|---|---|---|---|---|---|
| stack-robust | 127.5 | -11.0% | -16.8 .. -14.7 | 74 | -13 | 43.9% |
| stack | 128.3 | -10.4% | -16.0 .. -13.8 | 76 | -2 | 43.2% |
| debias | 139.9 | -2.3% | -3.9 .. -2.8 | 83 | -10 | 40.7% |
| stack-median | 142.9 | -0.3% | -1.1 .. +0.2 | 82 | -60 | 40.7% |
| full | 143.3 | +0.0% | - | 83 | -36 | 40.5% |
| no-prior | 144.9 | +1.1% | - | 83 | -81 | 41.0% |
| sections | 151.9 | +6.0% | - | 89 | -75 | 38.8% |
| api | 2613.4 | +1723.9% | - | 172 | -2317 | 23.7% |

## By horizon, MAE in seconds

| predictor | 0-1 | 1-2 | 2-5 | 5-10 | 10-20 | 20-45 |
|---|---|---|---|---|---|---|
| stack-robust | 16 | 27 | 43 | 73 | 122 | 211 |
| stack | 16 | 27 | 44 | 73 | 122 | 213 |
| debias | 18 | 30 | 49 | 82 | 136 | 228 |
| stack-median | 18 | 29 | 47 | 79 | 132 | 243 |
| full | 18 | 30 | 49 | 82 | 136 | 238 |
| no-prior | 16 | 27 | 44 | 75 | 130 | 253 |
| sections | 20 | 32 | 50 | 83 | 138 | 260 |
| api | 1082 | 1079 | 1077 | 1092 | 1380 | 5221 |

## How alike the members are, on the test window

A blend can only win where the errors disagree. Correlations near one mean the members are making the same mistake and there is nothing to average away.

| | full | no-prior | sections | api |
|---|---|---|---|---|
| full | 1.00 | 0.91 | 0.96 | 0.02 |
| no-prior | 0.91 | 1.00 | 0.91 | 0.05 |
| sections | 0.96 | 0.91 | 1.00 | 0.02 |
| api | 0.02 | 0.05 | 0.02 | 1.00 |

## The weights `stack-robust` fitted

| horizon | full | no-prior | sections | api | intercept s |
|---|---|---|---|---|---|
| 0-1 min | -0.51 | +1.58 | -0.07 | +0.00 | +1 |
| 1-2 min | -0.16 | +1.18 | -0.02 | +0.00 | +1 |
| 2-5 min | -0.05 | +0.99 | +0.06 | +0.00 | +5 |
| 5-10 min | -0.01 | +0.92 | +0.08 | -0.00 | +18 |
| 10-20 min | -0.03 | +0.84 | +0.19 | +0.00 | +50 |
| 20-45 min | +0.04 | +0.77 | +0.19 | +0.00 | +146 |

## The weights `stack` fitted

| horizon | full | no-prior | sections | api | intercept s |
|---|---|---|---|---|---|
| 0-1 min | -0.60 | +1.42 | +0.18 | +0.00 | -2 |
| 1-2 min | -0.25 | +1.04 | +0.21 | +0.00 | -3 |
| 2-5 min | -0.15 | +0.88 | +0.28 | +0.00 | +2 |
| 5-10 min | -0.12 | +0.82 | +0.29 | -0.00 | +17 |
| 10-20 min | -0.19 | +0.78 | +0.40 | +0.00 | +60 |
| 20-45 min | -0.11 | +0.77 | +0.34 | +0.00 | +189 |

## The weights `debias` fitted

| horizon | full | no-prior | sections | api | intercept s |
|---|---|---|---|---|---|
| 0-1 min | +1.00 | +0.00 | +0.00 | +0.00 | -3 |
| 1-2 min | +1.00 | +0.00 | +0.00 | +0.00 | -6 |
| 2-5 min | +1.00 | +0.00 | +0.00 | +0.00 | -6 |
| 5-10 min | +1.00 | +0.00 | +0.00 | +0.00 | -4 |
| 10-20 min | +1.00 | +0.00 | +0.00 | +0.00 | +8 |
| 20-45 min | +1.00 | +0.00 | +0.00 | +0.00 | +73 |
