# Correcting the model's residual

Fitted on the 141559 predictions emitted from 09-05 20:54 to 09-05 23:45, and scored on the 2757685 emitted from 09-06 05:46 to 09-06 18:56, covering 115264 crossings. Every model corrects the same physical model on the same rows, so the intervals are on the difference from it and not on either MAE.

| model | MAE s | vs full | 95% CI on the difference | median s | bias s | <60 s |
|---|---|---|---|---|---|---|
| full | 168.4 | +0.0% | - | 73 | -60 | 44.0% |
| resid-linear | 185.0 | +9.9% | +14.8 .. +18.3 | 80 | -135 | 42.0% |
| resid-const | 197.5 | +17.3% | +26.9 .. +31.1 | 88 | -154 | 39.4% |
| resid-quantile | 199.3 | +18.4% | +27.5 .. +34.5 | 87 | -133 | 39.6% |
| resid-gbm | 207.2 | +23.0% | +35.4 .. +42.3 | 97 | -122 | 37.3% |
| resid-mlp | 900.9 | +435.1% | +696.8 .. +772.4 | 478 | +80 | 10.4% |

## By horizon, MAE in seconds

| model | 0-1 | 1-2 | 2-5 | 5-10 | 10-20 | 20-45 |
|---|---|---|---|---|---|---|
| full | 17 | 29 | 46 | 76 | 122 | 208 |
| resid-linear | 17 | 27 | 43 | 70 | 118 | 252 |
| resid-const | 20 | 26 | 43 | 70 | 123 | 283 |
| resid-quantile | 17 | 28 | 46 | 77 | 129 | 288 |
| resid-gbm | 18 | 31 | 52 | 88 | 144 | 296 |
| resid-mlp | 32 | 80 | 178 | 379 | 757 | 1606 |

## The 80% prediction interval

The 0.1 and 0.9 quantiles of the same residual, read as an interval on the arrival time. Coverage should be 80%; width is what the band costs to say; pinball loss is the proper score that trades the two and the only column models can be ranked by.

| band | coverage | width s | median width s | pinball 0.1 | pinball 0.9 | edges crossed |
|---|---|---|---|---|---|---|
| band-const | 76.1% | 399 | 373 | 37.0 | 83.6 | 0.0% |
| band-quantile | 59.3% | 300 | 233 | 34.1 | 95.0 | 0.3% |

Coverage and mean width by horizon:

| band | 0-1 | 1-2 | 2-5 | 5-10 | 10-20 | 20-45 |
|---|---|---|---|---|---|---|
| band-const | 72% / 93 s | 87% / 111 s | 87% / 164 s | 86% / 251 s | 82% / 392 s | 67% / 619 s |
| band-quantile | 70% / 46 s | 81% / 89 s | 78% / 143 s | 72% / 216 s | 63% / 306 s | 43% / 430 s |

## What carries resid-linear

Each group of features is blanked and the model refitted; the cost is what the correction loses without it.

| dropped | MAE s | cost s |
|---|---|---|
| none | 185.0 | +0.0 |
| horizon | 308.9 | +123.9 |
| evidence | 191.1 | +6.1 |
| vehicle | 184.9 | -0.1 |
| timetable | 183.4 | -1.5 |
| context | 188.4 | +3.5 |
