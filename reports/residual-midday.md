# Correcting the model's residual

Fitted on the 1345038 predictions emitted from 09-05 20:54 to 09-06 11:59, and scored on the 1554206 emitted from 09-06 12:00 to 09-06 18:56, covering 65254 crossings. Every model corrects the same physical model on the same rows, so the intervals are on the difference from it and not on either MAE.

| model | MAE s | vs full | 95% CI on the difference | median s | bias s | <60 s |
|---|---|---|---|---|---|---|
| resid-quantile | 145.5 | -9.8% | -20.1 .. -11.6 | 66 | -32 | 47.0% |
| resid-gbm | 154.6 | -4.1% | -13.2 .. +0.4 | 70 | -19 | 45.4% |
| resid-linear | 159.7 | -1.0% | -3.0 .. -0.3 | 72 | -64 | 44.3% |
| full | 161.2 | +0.0% | - | 70 | -70 | 45.1% |
| resid-const | 163.3 | +1.3% | +1.5 .. +2.6 | 71 | -84 | 44.9% |
| resid-mlp | 200.5 | +24.3% | +29.8 .. +47.6 | 96 | +6 | 37.1% |

## By horizon, MAE in seconds

| model | 0-1 | 1-2 | 2-5 | 5-10 | 10-20 | 20-45 |
|---|---|---|---|---|---|---|
| resid-quantile | 18 | 29 | 45 | 70 | 108 | 182 |
| resid-gbm | 18 | 29 | 45 | 74 | 119 | 202 |
| resid-linear | 20 | 32 | 48 | 73 | 111 | 192 |
| full | 17 | 28 | 44 | 72 | 114 | 196 |
| resid-const | 21 | 27 | 44 | 70 | 111 | 201 |
| resid-mlp | 20 | 33 | 54 | 96 | 164 | 288 |

## The 80% prediction interval

The 0.1 and 0.9 quantiles of the same residual, read as an interval on the arrival time. Coverage should be 80%; width is what the band costs to say; pinball loss is the proper score that trades the two and the only column models can be ranked by.

| band | coverage | width s | median width s | pinball 0.1 | pinball 0.9 | edges crossed |
|---|---|---|---|---|---|---|
| band-quantile | 67.2% | 279 | 212 | 29.8 | 53.1 | 0.1% |
| band-const | 82.2% | 403 | 372 | 31.0 | 74.2 | 0.0% |

Coverage and mean width by horizon:

| band | 0-1 | 1-2 | 2-5 | 5-10 | 10-20 | 20-45 |
|---|---|---|---|---|---|---|
| band-quantile | 65% / 45 s | 76% / 83 s | 75% / 129 s | 72% / 195 s | 69% / 276 s | 63% / 383 s |
| band-const | 68% / 90 s | 84% / 105 s | 84% / 154 s | 86% / 253 s | 85% / 393 s | 83% / 629 s |

## What carries resid-quantile

Each group of features is blanked and the model refitted; the cost is what the correction loses without it.

| dropped | MAE s | cost s |
|---|---|---|
| none | 145.5 | +0.0 |
| horizon | 150.0 | +4.5 |
| evidence | 165.4 | +20.0 |
| vehicle | 153.6 | +8.1 |
| timetable | 152.4 | +6.9 |
| context | 150.9 | +5.5 |
