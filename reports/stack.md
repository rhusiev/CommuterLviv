# Blending the predictors

Weights fitted on the 125841 predictions emitted from 09-05 20:58 to 09-05 23:45, and everything scored on the 2391111 emitted from 09-06 05:49 to 09-06 18:56, covering 109525 crossings. Members and blends answer the identical rows, so the interval is on the difference from `full` rather than on either MAE.

| predictor | MAE s | vs full | 95% CI on the difference | median s | bias s | <60 s |
|---|---|---|---|---|---|---|
| stack-robust | 107.6 | -7.8% | -10.3 .. -7.6 | 59 | -43 | 50.4% |
| stack-median | 111.3 | -4.7% | -6.3 .. -4.6 | 63 | -32 | 48.7% |
| no-prior | 112.2 | -3.8% | - | 64 | -60 | 48.1% |
| full | 116.7 | +0.0% | - | 66 | -11 | 47.0% |
| stack | 117.4 | +0.6% | -2.1 .. +3.7 | 63 | -52 | 48.5% |
| sections | 119.9 | +2.8% | - | 68 | -53 | 46.1% |
| debias | 126.2 | +8.2% | +8.6 .. +10.4 | 74 | -59 | 43.6% |
| full+quantile | 138.2 | +18.5% | +19.0 .. +23.9 | 76 | -71 | 43.1% |
| api | 575.1 | +392.8% | - | 153 | -209 | 26.7% |

## By horizon, MAE in seconds

| predictor | 0-1 | 1-2 | 2-5 | 5-10 | 10-20 | 20-45 |
|---|---|---|---|---|---|---|
| stack-robust | 15 | 25 | 39 | 64 | 103 | 198 |
| stack-median | 17 | 27 | 43 | 69 | 112 | 196 |
| no-prior | 15 | 25 | 39 | 65 | 110 | 207 |
| full | 17 | 29 | 46 | 75 | 120 | 201 |
| stack | 17 | 27 | 44 | 67 | 113 | 218 |
| sections | 19 | 30 | 46 | 73 | 118 | 215 |
| debias | 18 | 29 | 47 | 77 | 126 | 226 |
| full+quantile | 17 | 28 | 46 | 75 | 126 | 270 |
| api | 407 | 422 | 448 | 497 | 572 | 737 |

## How alike the members are, on the test window

A blend can only win where the errors disagree. Correlations near one mean the members are making the same mistake and there is nothing to average away.

| | full | no-prior | sections | api |
|---|---|---|---|---|
| full | 1.00 | 0.87 | 0.94 | 0.09 |
| no-prior | 0.87 | 1.00 | 0.87 | 0.05 |
| sections | 0.94 | 0.87 | 1.00 | 0.11 |
| api | 0.09 | 0.05 | 0.11 | 1.00 |

## The weights `stack-robust` fitted

| horizon | full | no-prior | sections | api | intercept s |
|---|---|---|---|---|---|
| 0-1 min | -0.56 | +1.48 | +0.08 | -0.00 | +0 |
| 1-2 min | -0.25 | +1.06 | +0.19 | -0.00 | -1 |
| 2-5 min | -0.19 | +0.84 | +0.35 | +0.00 | +2 |
| 5-10 min | -0.16 | +0.70 | +0.46 | +0.00 | +8 |
| 10-20 min | -0.17 | +0.66 | +0.51 | -0.00 | +26 |
| 20-45 min | -0.09 | +0.41 | +0.64 | +0.03 | +40 |

## The weights `stack` fitted

| horizon | full | no-prior | sections | api | intercept s |
|---|---|---|---|---|---|
| 0-1 min | -0.80 | +1.27 | +0.54 | +0.00 | -2 |
| 1-2 min | -0.45 | +0.95 | +0.50 | -0.01 | -6 |
| 2-5 min | -0.40 | +0.76 | +0.66 | -0.01 | -5 |
| 5-10 min | -0.34 | +0.62 | +0.73 | -0.00 | +2 |
| 10-20 min | -0.25 | +0.65 | +0.56 | +0.03 | +20 |
| 20-45 min | -0.09 | +0.43 | +0.56 | +0.09 | +40 |

## The weights `debias` fitted

| horizon | full | no-prior | sections | api | intercept s |
|---|---|---|---|---|---|
| 0-1 min | +1.00 | +0.00 | +0.00 | +0.00 | -5 |
| 1-2 min | +1.00 | +0.00 | +0.00 | +0.00 | -12 |
| 2-5 min | +1.00 | +0.00 | +0.00 | +0.00 | -19 |
| 5-10 min | +1.00 | +0.00 | +0.00 | +0.00 | -30 |
| 10-20 min | +1.00 | +0.00 | +0.00 | +0.00 | -48 |
| 20-45 min | +1.00 | +0.00 | +0.00 | +0.00 | -84 |
