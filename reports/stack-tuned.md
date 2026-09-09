# Blending the predictors

Weights fitted on the 125839 predictions emitted from 09-05 20:58 to 09-05 23:45, and everything scored on the 2391065 emitted from 09-06 05:49 to 09-06 18:56, covering 109525 crossings. Members and blends answer the identical rows, so the interval is on the difference from `full` rather than on either MAE.

| predictor | MAE s | vs full | 95% CI on the difference | median s | bias s | <60 s |
|---|---|---|---|---|---|---|
| stack-median | 109.3 | -6.3% | -8.4 .. -6.4 | 61 | -44 | 49.6% |
| no-prior | 112.2 | -3.8% | - | 64 | -60 | 48.1% |
| tuned | 113.3 | -2.9% | - | 62 | -72 | 48.9% |
| full | 116.7 | +0.0% | - | 66 | -11 | 47.0% |
| sections | 119.9 | +2.8% | - | 68 | -53 | 46.1% |
| stack-robust | 122.4 | +4.9% | +1.2 .. +10.3 | 60 | -73 | 49.9% |
| stack | 123.3 | +5.7% | +2.0 .. +11.4 | 61 | -69 | 49.2% |
| debias | 126.2 | +8.2% | +8.6 .. +10.4 | 74 | -59 | 43.6% |
| full+quantile | 138.2 | +18.5% | +19.0 .. +23.9 | 76 | -71 | 43.1% |
| api | 575.0 | +392.8% | - | 153 | -209 | 26.7% |

## By horizon, MAE in seconds

| predictor | 0-1 | 1-2 | 2-5 | 5-10 | 10-20 | 20-45 |
|---|---|---|---|---|---|---|
| stack-median | 16 | 26 | 40 | 66 | 108 | 197 |
| no-prior | 15 | 25 | 39 | 65 | 110 | 207 |
| tuned | 15 | 24 | 38 | 63 | 108 | 215 |
| full | 17 | 29 | 46 | 75 | 120 | 201 |
| sections | 19 | 30 | 46 | 73 | 118 | 215 |
| stack-robust | 15 | 24 | 38 | 64 | 109 | 245 |
| stack | 16 | 26 | 41 | 66 | 120 | 233 |
| debias | 18 | 29 | 47 | 77 | 126 | 226 |
| full+quantile | 17 | 28 | 46 | 75 | 126 | 270 |
| api | 407 | 422 | 448 | 497 | 572 | 737 |

## How alike the members are, on the test window

A blend can only win where the errors disagree. Correlations near one mean the members are making the same mistake and there is nothing to average away.

| | full | no-prior | sections | tuned | api |
|---|---|---|---|---|---|
| full | 1.00 | 0.87 | 0.94 | 0.91 | 0.09 |
| no-prior | 0.87 | 1.00 | 0.87 | 0.93 | 0.05 |
| sections | 0.94 | 0.87 | 1.00 | 0.92 | 0.11 |
| tuned | 0.91 | 0.93 | 0.92 | 1.00 | 0.09 |
| api | 0.09 | 0.05 | 0.11 | 0.09 | 1.00 |

## The weights `stack-robust` fitted

| horizon | full | no-prior | sections | tuned | api | intercept s |
|---|---|---|---|---|---|---|
| 0-1 min | -0.91 | +0.78 | +0.22 | +0.91 | +0.00 | +1 |
| 1-2 min | -0.59 | +0.51 | +0.24 | +0.84 | -0.00 | -0 |
| 2-5 min | -0.50 | +0.34 | +0.38 | +0.78 | +0.00 | +3 |
| 5-10 min | -0.48 | +0.25 | +0.41 | +0.81 | +0.01 | +11 |
| 10-20 min | -0.45 | +0.28 | +0.34 | +0.79 | +0.03 | +28 |
| 20-45 min | -0.35 | +0.09 | +0.26 | +0.86 | +0.13 | +38 |

## The weights `stack` fitted

| horizon | full | no-prior | sections | tuned | api | intercept s |
|---|---|---|---|---|---|---|
| 0-1 min | -1.24 | +0.61 | +0.58 | +1.04 | +0.00 | -1 |
| 1-2 min | -0.80 | +0.52 | +0.52 | +0.76 | -0.00 | -3 |
| 2-5 min | -0.75 | +0.38 | +0.67 | +0.72 | -0.01 | -0 |
| 5-10 min | -0.69 | +0.22 | +0.65 | +0.82 | +0.01 | +10 |
| 10-20 min | -0.57 | +0.25 | +0.38 | +0.88 | +0.07 | +32 |
| 20-45 min | -0.35 | +0.14 | +0.32 | +0.76 | +0.13 | +58 |

## The weights `debias` fitted

| horizon | full | no-prior | sections | tuned | api | intercept s |
|---|---|---|---|---|---|---|
| 0-1 min | +1.00 | +0.00 | +0.00 | +0.00 | +0.00 | -5 |
| 1-2 min | +1.00 | +0.00 | +0.00 | +0.00 | +0.00 | -12 |
| 2-5 min | +1.00 | +0.00 | +0.00 | +0.00 | +0.00 | -19 |
| 5-10 min | +1.00 | +0.00 | +0.00 | +0.00 | +0.00 | -30 |
| 10-20 min | +1.00 | +0.00 | +0.00 | +0.00 | +0.00 | -48 |
| 20-45 min | +1.00 | +0.00 | +0.00 | +0.00 | +0.00 | -84 |
