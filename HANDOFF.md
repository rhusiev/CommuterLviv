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
| [mobile/README.md](mobile/README.md) | only if you are touching the phone app: how to run it on a phone or on the emulator, and the seven things to know before changing it |
| [PLAN.md](PLAN.md) | the approach comparison, phase by phase, with every item's status. **Reread it after every compaction** |
| [reports/findings.md](reports/findings.md) | what the numbers turned out to mean. Fifteen findings, each with the measurement behind it |
| [reports/approaches.md](reports/approaches.md) | the current scoreboard |
| [reports/residual.md](reports/residual.md) and [-midday](reports/residual-midday.md) | Phase 4's two splits: what an offline model of the model's own error is worth |
| [reports/stack.md](reports/stack.md) and [-midday](reports/stack-midday.md) | Phase 5's same two splits: what blending the predictors is worth, and the weights it fits |

Everything else is derived: `reports/approaches.json`, `reports/sweeps.json` and
the `residual*.json` and `stack*.json` are machine-readable copies of the report
tables.

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

## State of play, 2026-09-09

- **The collector now runs on the VPS, not on this machine**, and it is off in
  `docker-compose.yml` unless `--profile collect` asks for it, because two
  machines recording the same feed produce two recordings neither of which is a
  superset of the other. The three that existed have been folded into one:
  `data/feed.db` is now 3.98 days, 318 068 polls, 8 574 744 vehicle rows and
  39 839 957 predictions, built by `commuterlviv merge`, which takes the first
  source's version of any instant and reads a later one only inside a hole
  longer than 30 s. Phase 6 is no longer blocked.

  The source recordings are gone as of 2026-09-10; `data/feed.db` is the only
  copy. **The merge is lossy on purpose and the merged file is not a superset of
  its sources.** Checked before deleting the last one, `feed-host-early.db`: over
  its own window `feed.db` holds 75 489 polls against its 75 433, 1 430 017
  vehicle rows against 1 429 068 and 399 924 board rows against 399 025 - but
  10 559 *fewer* predictions, 7 117 676 against 7 128 235. That is the policy
  working, not a bug. `pred` has no unique constraint, so the `INSERT OR IGNORE`
  cannot be deduplicating (the early file's 7 128 235 rows are 7 128 235
  distinct rows); the seconds both machines covered were won by whichever source
  came first, and its samples of those seconds are slightly fewer. Concatenating
  instead would double the apparent update rate, which several predictors read.
- **Phases 0-5 are done and scored, and Phase 6 rescored them on the six-day
  recording.** `profile` now leads at 134 s MAE and is the only switch that beats
  `full` (138); the official API is far behind at 1432. **`tuned`, which led the
  single day at 114 against 120, is now +4% and beaten by the model it beat** -
  it still wins every horizon out to 20 minutes and still loses 20-45 min, but
  that bucket is a larger share of six days than of one. A constant tuned on one
  day was fitted to that day, which is the question Phase 6 existed to answer.
  Phase 4's residual models are scored on two splits and finding 9 says
  what they mean. Phase 5's blends are scored on the same two splits, and
  `stack-robust` is the largest win the project has measured: 8% on the harder
  split, 13% on the easier one, finding 10. See `PLAN.md`.
- **Nothing from Phase 4 or 5 has been merged into the shipped predictor**, and
  the reason is the same for both: everything is fitted and used inside a single
  day's recording. Phase 6 is what decides whether any of it survives.
- **One Phase 6 item was brought forward and it repairs the morning.**
  `slow-day` - a third EWMA with a half-life of a day beneath the existing two -
  scores 109 s against `full`'s 134 on the morning after a night, -18%. Over the
  whole recording it is 113 against 118, tied with `no-prior` and `tuned` but
  with a much smaller bias, -51 s against -58 and -68. Finding 11. It did not
  need multi-day data because the recording already contains one night. The rest
  of Phase 6 is still blocked.
- **A live service and a web UI were requested on 2026-09-06** and are Phase 7
  in `PLAN.md`. All three open questions are answered - the push load is
  negligible, the user chose accounts anyway, and it is Python - and the
  **both halves are written and tested**: `commuterlviv/live/`, served by
  `commuterlviv serve`, and `web/`, driven end to end in a headless browser.
- **A phone app was requested on 2026-09-07** and is Phase 8. `mobile/` is
  written, analyzes clean, its wire tests pass, it builds a release APK, and on
  2026-09-08 it was driven on an Android 15 emulator against the dev stack -
  registration, the live map, the route sheet, the times and the style switcher.
  It is also installed on the user's own phone, from a debug APK pointed at the
  VPN address - debug because the release manifest forbids cleartext and this
  deployment has no certificate. The licence is MIT and the app defaults to `https://commuterlviv.r1a.nl`; the
  two things still blocking an F-Droid submission are that the project has no
  public repository, so the recipe's URLs are placeholders, and no tags, so
  there is no commit for it to build. The recipe itself is lint-clean and
  `mobile/README.md` has the steps.
- **The whole stack is now one command.** `docker compose up -d --build` brings
  up Postgres, the service, the collector and Caddy in front; the dev overlay
  swaps the built UI for Vite's dev server and opens the ports. Verified end to
  end against a scratch project, down to a websocket carrying frames. Guides for
  both are in `README.md`.

- **Phase 9, the six things the user asked for on 2026-09-09, are all in**, at
  version 0.3.0. The journey planner now builds its own `walk.npz` and
  `transfers.npz` on a fresh volume, in a background task, once
  (`COMMUTERLVIV_BUILD_PLANNER=false` turns it off), which is why
  `/api/plan` answered 503 on the VPS. Every icon of all three clients comes out
  of `tool/icons.sh` and `web/public/icon.svg`. The language switches without a
  restart. The map's attribution is a permanent ⓘ badge rather than a strip.
  Both clients share one palette. The recording is merged, the collector is
  behind a compose profile, and Caddy now overwrites `X-Forwarded-For` instead
  of appending to it, which had let a caller pick its own rate-limit bucket.

- **A review pass over the whole codebase**, at version 0.3.1, asked for on
  2026-09-10. Nine fixes, all small and all defensive: Android backup is off
  (shared preferences held a session cookie and a sixty-day remember-me token);
  `register()` and route-set `create()` now catch the unique index instead of
  checking first, which two racing requests could get between; a request body is
  measured while it streams rather than after it is all in memory; `/api/plan`
  bounds itself to four searches and refuses the fifth; an account may hold
  eight sockets; two `int()` calls on unbounded query strings were 500s; a GTFS
  error page no longer overwrites the cached feed and `table()` no longer leaks
  a handle per call; the arrivals row-mapping and the admin pool setup were each
  written twice and are now written once. `README.md` gained a table of every
  host the deployment talks to, and the phone gained the self-hosted-tiles
  escape hatch the web already had - as a build define at the time, which 0.3.4
  replaced with something the client asks for.

- **The four judgement calls from that pass are closed too**, at 0.3.2. The
  phone's cookie jar moved from `SharedPreferences` to `flutter_secure_storage`,
  which is the Android Keystore and the iOS Keychain; an existing jar is
  migrated on first open rather than dropped, so nobody is signed out by the
  upgrade. `/api/status` needs an operator flag - migration `002_operator.sql`,
  granted with `admin operator <name>`, and a 404 rather than a 403 to anyone
  without it. `call()` in `web/src/lib/api.ts` is generic and `live.ts` names
  the one text frame it reads, so there is no `any` left in the web tree.
  `gtfs.py` is on `pathlib`.

  Verified against a real stack, not just `check.sh`: `check_live.py` 44/44 and
  `check_web.py` all green on the dev compose overlay, plus a hand check that an
  operator gets 200 from `/api/status` where an ordinary account gets 404.

- **The VPS runs 0.3.2** as of 2026-09-10. It was on 0.2.0. Deployed by rsync
  (excluding `data`, `.env`, build trees) then a rebuild of
  `docker-compose.yml + docker-compose.proxy.yml`; the previous tree is at
  `/opt/commuterlviv/app-backup-2026-09-10-0654.tar.gz`. Migration 002 applied
  cleanly, and `rad1an` is an operator.

- **The `.env` exclusion above is not optional.** A deploy on 2026-09-11 left it
  out, and the laptop's `.env` replaced the server's: the Postgres password,
  `CADDY_NETWORK`, `COMMUTERLVIV_TILES` and `COMMUTERLVIV_VARIANT` all went with
  it, so the service crash-looped on `InvalidPasswordError` and the tile server
  on a missing `/tiles/lviv.versatiles`. The file came back out of
  `/opt/commuterlviv/app-backup-2026-09-11-0732.tar.gz`. The two files are
  different deployments, not drifted copies of one.

- **The VPS runs 0.3.4**, and serves its own basemap. No phone or browser talks
  to `tiles.versatiles.org` any more. A 20 MB Lviv extract
  (`--bbox 23.791,49.702,24.233,50.045`, 1400 tiles, maxzoom 14) plus the v3.14
  frontend archive live in `/opt/commuterlviv/tiles`; `docker-compose.tiles.yml`
  runs `versatiles serve` beside the stack with no published port, and Caddy's
  `handle_path /tiles/*` puts it on the app's own origin.

  **Nothing is compiled in.** The overlay sets `COMMUTERLVIV_SELF_TILES` on the
  service, `/api/health` reports it beside `registration`, and both clients ask
  before drawing a map - web at `main.tsx` before the first render, the phone in
  `main()` because a resumed session never reaches the sign-in screen. So one
  web image and one APK work under any domain, and pointing the phone at another
  deployment follows that deployment's map. 0.3.3 got this wrong: it baked
  `commuterlviv.r1a.nl` into both artifacts through build-time defines, which
  are gone.

  The style files are the one thing that must name the host, because
  `vector_map_tiles`'s `uri_mapper.dart` parses style URIs with `Uri.parse` and
  never calls `.resolve()` - a relative sprite or tile URL would break the phone.
  So `deploy/tiles-setup.sh <site> [dir]` generates them at setup time from the
  address given once, and nothing is committed. That script also cuts the
  extract and fetches the frontend; it is re-runnable and keeps the extract.

  Verified live at 0.3.4: `/api/health` reports `"tiles":true`, the bundle
  contains no `r1a.nl` at all, and styles, glyphs, sprites and real tiles at
  z10/z12/z14 all 200. The 0.3.4 APK on `/download/` carries no tile host.

- **Login was broken on production for about three hours on 2026-09-10**, from
  the 0.3.2 deploy until 0.3.5, and the cause is worth remembering. The
  Caddyfile asked for the forwarded address as `{$COMMUTERLVIV_CLIENT_IP:{remote_host}}`.
  Caddy's env-var syntax ends at the **first** `}`, so it read the default as
  `{remote_host` and left the spare `}` in the header. `auth_events.ip` is an
  `inet` column, the failed-login audit write is on the login path, and asyncpg
  refused `172.19.0.1}` - so every sign-in returned 500 and no failure was ever
  recorded, which is what made it invisible. The line had been wrong since
  0.3.0; production only reached it today, because the VPS had been on 0.2.0.

  The default now lives in `docker-compose.yml`, and `_address()` in `app.py`
  validates the header so a bad one can only cost an audit field. `check_live.py`
  posts a login with `X-Forwarded-For: not-an-address}` and asserts 401.

  Separately, and **corrected on 2026-09-10**: the outer Caddy sets
  `X-Forwarded-For {remote_host}` correctly and does see real client addresses.
  An earlier note here said every client arrived as the Docker gateway
  `172.19.0.1`; that is only true of requests that hairpin - from the host
  itself, from another container, or from a VPN client whose packet leaves for
  the public address and is DNATed back into the bridge, where Docker's
  hairpin MASQUERADE rewrites the source to the gateway. Caddy's own log has
  ordinary internet clients under their real address (`194.44.253.166`) beside
  those. So rate limiting is per client for everyone off the VPN, and one
  shared bucket for everyone on it.

  Fixing the VPN half needs root on the VPS - there is no sudo - or a change to
  how wg-easy routes, so it is left alone. The one clean fix, if it ever
  matters, is to stop VPN clients hairpinning at all: give them the app's VPN
  address directly rather than the public name.

- **Production is recording**, from 2026-09-10 06:52. The collector runs behind
  the `collect` profile (`--profile collect up -d collector`, `--keep-days 30
  --min-free-gb 3`, 77 GB free) and appends to the `feed.db` already on the
  volume - same path, `CREATE TABLE IF NOT EXISTS`. The existing rows span
  2026-09-05 17:17 to 09-09 16:55, well inside the 30-day window, so none of it
  is pruned. There is a gap from 09-09 16:55 to 09-10 06:52, where the service
  ran without a collector.

  It failed on the first start, and the reason is worth knowing: `feed.db` had
  been copied into the volume from the host and kept **uid 1000**, while the
  containers run as uid **10001**. SQLite reports that as
  `attempt to write a readonly database`, which names neither the file nor the
  permission, and the service had never noticed because it only reads. Fixed
  with a root container over the volume - there is no sudo on the VPS - and
  written up in `docs/05-gotchas.md`. Confirmed appending afterwards: the file
  grew 5 370 191 872 -> 5 395 030 016 bytes with no write errors.

  One catch, also in `docs/05-gotchas.md`: the file reports `auto_vacuum: 0`,
  because the pragma `collect.py` sets only takes on an empty database and this
  one came from `merge.py`. Pruning will bound the rows but not the bytes, so
  `--min-free-gb` is the guard that actually stops it.

- **Both clients were redesigned to float**, at 0.4.0, asked for on 2026-09-10
  with the Telegram redesign and Google Maps as the examples. One rule: nothing
  is docked to an edge. The map is the whole window and every piece of chrome -
  the top bar, the tab pill, the drawers, the cards, the sheets - is a rounded
  translucent surface over it. The rule is stated once per client, in
  `web/src/app.css`'s `@theme` comment and `mobile/lib/src/theme.dart`'s library
  doc, and the geometry with it: `floatingTop`/`floatingBottom` on the phone,
  `top-19`/`bottom-20` on the web.

  The shape of both changed, not just the paint. The web layout is one
  `relative` box of absolutely positioned pieces rather than a column; the tab
  switcher moved to a bottom-centre pill and sign-out into the routes drawer,
  because the old header was ~540 px of controls and a phone is 360. The
  `Scaffold` has neither an `appBar` nor a `bottomNavigationBar` any more, every
  sheet goes through `showFloatingSheet` in `sheets.dart` (a transparent sheet
  with the gap as padding inside it, and its own drag handle, because
  `showModalBottomSheet` is docked by construction), and `RoundButton` in
  `theme.dart` is the one definition of a floating round button.

  `check.sh` green, both screenshotted headless at 1100x700 and 390x780.

- **A route says what kind of vehicle it is with a glyph**, at 0.4.2. The city
  writes the kind as the letter in front of the number - `А25` a bus, `Т07` a
  tram, `Тр33` a trolleybus - which is only readable to someone who knows that
  and reads Cyrillic. `routeNumber` strips it in both clients and `RouteBadge`
  draws the kind instead, from three line drawings in the same 24-unit box,
  because no icon set has a trolleybus. The map badge is the number alone: a
  26 px circle has no room for a glyph, and the hue was already saying it. That
  also buys the map badge a font size - three characters where four used to go.

  Also 0.4.1: with the drawer open, the stop card and the timetable centred on
  the window rather than on the map left over and sat flush against it.

- **Nothing resizes when you press it**, at 0.4.3, asked for on 2026-09-10. Four
  places changed size on their own state, which moves whatever sits beside them
  under a thumb that is still on the screen: the tab bar bolded the chosen tab
  in both clients, and a heavier label is a wider one; the phone's route and set
  chips grew a Material checkmark when selected (`showCheckmark: false` - the
  colour was already saying it); and the web's pin button said "pin" or
  "pinned", two different widths, so it and the ✕ beside it jumped. The pin is
  now the same filled-or-outlined thumbtack the phone card already used, and
  `t.pinned` is gone from both dictionaries.

  Interchangeable buttons are equal width where the members are alike: the three
  tabs (`grid-cols-3` on the web, `IntrinsicWidth` over `Expanded` children on
  the phone - that combination asks the row for the widest child per flex unit,
  so the bar stays only as wide as it must be, verified in a throwaway test) and
  the route number in a badge, which has a floor of two digits, 71 of the 72
  routes. Not the basemap or language buttons: their labels are genuinely
  different lengths and "Українська" would give "English" a field of empty pill.

- **A route's own line, and every route at once**, at 0.4.4, asked for on
  2026-09-10. Tapping the badge on a vehicle card opens a fourth tab holding
  that route: its polylines in the route's colour, direction arrows along them,
  and only that route's vehicles - which needed no server code, because the
  socket already takes a route filter and the view just sends a filter of one.
  The camera fits the route's bounds on open; a route is tens of kilometres long
  and wherever the map happened to be is not on it. A second button on the map
  draws every route's line at once, dimmed and without arrows, because 72 routes
  of arrowheads is a texture and not information.

  Geometry comes from `GET /api/shapes` (`live/geometry.py`), fetched lazily and
  held against its ETag next to the catalog. The server spaces arrows 220 m
  apart, which at the zoom that holds a whole route is five pixels - the line
  reads as dashed - so both clients drop to every nth arrow for roughly 80 px of
  spacing and draw none at all below zoom 13. Arrowheads are drawn in the page's
  ink, not the route's colour: a coloured head on a line of the same colour is
  nothing at all. A two-way stretch gets two heads backed 9 px off each other,
  which reads as `-><-`; closer together they read as a diamond.

- **The recording covers five service days now, and scoring it day by day
  reverses three published conclusions**, at 0.4.5, asked for on 2026-09-10.
  `commuterlviv crossday` replays each approach once over the whole recording,
  so the online models carry across the nights as they would in service, and
  cuts the score by the service day each prediction was made on - the day
  rolling at 03:00, because the last trams run past midnight and nothing runs
  until 05:30. On the three full weekdays `full` is first or tied first;
  `tuned` loses by 6-12 s, `slow-day` by 6-13, and `knn`'s lead is gone. All
  three of those had been measured on a Saturday evening and a Sunday, and the
  whole field is 25-35 s worse on a weekday than on that Sunday - which is the
  size of the effect that was being read as a difference between approaches.
  Nothing shipped on the old numbers, which is the one thing the plan got right
  about them. `reports/crossday.md`, finding 14.

  **The second pass put all 21 variants in one replay, and it changed what is
  served.** `profile` - `full` with a week-long hour-of-day pace profile where
  the corridor term stood - wins all five days and all three weekdays: 138.9,
  136.8 and 144.4 against `full`'s 140.7, 141.4 and 149.1, and 134.3 against
  138.2 pooled. It is finding 6's remedy in the form that works, where
  `slow-day`'s one-number-per-cell version of the same idea loses every weekday.
  `COMMUTERLVIV_VARIANT` now defaults to `profile` in `docker-compose.yml`, and
  the VPS serves it. The intervals in the report are each variant's own, not an
  interval on the difference; the series share an identical support event for
  event, but a paired interval would cost another three-hour replay.

  The first thing rechecked on a weekday split was the corridor grid, and it
  went the same way: `stack --grid 45` fitted on Monday and tested on Tuesday
  puts `stack-robust` at 128.1 s against 127.5 at the shipped 120 m, so the
  sweep's 2.3 s win on `full` does not survive the blend and
  `network.DEFAULT.grid` stays where it is.

  `commuterlviv experiment` also publishes MAE by the hour of day the
  prediction was made in, dropping any hour under 300 paired predictions, which
  is the table finding 6 asked for and the sparse hours used to forbid.

## What just landed, and what it enables

**Phase 5, the blends.** `commuterlviv/stack.py` replays `full`, `no-prior` and
`sections` in parallel, adds the operator's `api`, reduces the four to one panel
of errors on the crossings and instants all of them answered, and fits a
weighted average per horizon bucket on predictions emitted before the split.

```sh
python3 -m commuterlviv stack                            # the plan's split, ~8 min
python3 -m commuterlviv stack --fit-to 2026-09-06T12:00 \
    --test-from 2026-09-06T12:00 --label midday      # the same, split at noon
```

Blending is arithmetic on the errors rather than on the ETAs: the members share
a truth, so a weighted mean of their errors is the error of the weighted mean of
their predictions, and no arrival times need carrying. Weights sum to one by
construction - one member is the base, the others enter as differences - so a
blend is always an average and never a rescaling, and a per-bucket intercept
carries the level.

**`stack-robust` wins on both splits and is the largest measured win in the
project**: 107.6 s against `full`'s 116.7 on the plan's split, -9.0 [-10.3,
-7.6], and 95.2 against 109.7 at midday, -14.4 [-15.7, -13.2]. The same weights
fitted under squared loss are worth as much at midday and *nothing* on the plan's
split, +0.8 [-2.1, +3.7]. The control, `debias` - `full` with only the intercept
fitted - costs +9.5 s on the plan's split, so none of the win is levelling; the
evening's bias is the wrong sign the next morning. `api` earns a weight of about
zero everywhere despite correlating 0.03-0.11 with the rest: a member has to be
different *and* good. Finding 10 has the reading.

**Phase 4, end to end.** `commuterlviv/features.py` plus a hook in `replay.py` write
one row per emitted prediction, fourteen columns, all of them causally available
at the moment the prediction was made; `commuterlviv/residual.py` fits five models
of the residual on those rows and scores them in seconds against the uncorrected
model.

```sh
python3 -m commuterlviv features --out reports/feats.npz    # 4 min, 3 010 244 rows
python3 -m commuterlviv residual                            # the plan's split
python3 -m commuterlviv residual --fit-to 2026-09-06T12:00 \
    --test-from 2026-09-06T12:00 --label midday         # the split that answers
```

Rows are appended in the same loop and under the same mask as the predictions,
so feature row *i* is prediction row *i* and the join to the ground truth is by
position, never by a key - `predictors.event_of` supplies the crossing id.
`features.load(path)` returns a `Rows`, which carries the feature matrix, the
clipped log-ratio target, the inverse-gap weight, the emit time, the crossing,
the crossing's actual time and its trip. The last two are why it is a class
rather than the tuple it used to be: a correction has to be scored in seconds
against what really happened, and the clipped target cannot be inverted back to
it.

**The result is in finding 9 and it is two-sided.** On the plan's split - fit on
three evening hours, score on the whole next day - every model is worse than
doing nothing. On a split at midday, `resid-quantile` is worth 9.8%, -15.8 s
[-20.1, -11.6]. The gain is the loss function, not the model class: the residual
is right-skewed, MAE is minimised by the median, and the same trees under
squared loss get [-13.2, +0.4], which does not separate from zero. The ablation
says the correction is mostly reading the model's own evidence weights - how
much live data the ETA rested on - rather than anything about the city.

**Since then: `slow-day`, the interval, and a fifth stack member that does not
work.** `Config.day_hl` (0 = off) puts a third `Ewma` under the cell and
corridor scales, so what a cell learned yesterday still weighs something at
06:00; `Layer` now assembles its terms in `_cells`/`_corrs` rather than
branching on `fast` twice. `residual.py` gained the 0.1/0.9 band - `band-const`,
a weighted empirical quantile per horizon bucket, and `band-quantile`, two
quantile-loss tree fits - graded by coverage, width and the check loss at each
edge. `band-const` covers 76.1% and 82.2% of predictions against the 80% target on
the two splits; the fitted band covers 59.3% and 67.2%, because the `1/gap`
fitting weight puts its edges where the short horizons want them (finding 12).
Adding `tuned` to `stack.MEMBERS` buys 0.9 s at midday and costs 6 to 15 s
across a night, so the stack keeps its four members.

**The geometry constants moved onto the network and became sweepable.**
`network.Geometry` holds `cell`, `grid` and `octants`; `network.regrid(net,
geom)` rebuilds only the three affected arrays per shape, which is 0.2 s rather
than a full build, because the stop assignment that dominates a build does not
depend on them. `replay.run_many` therefore accepts one network per config, and
`sweep cell|grid|octants` works like any other sweep. This is sound only because
tracking and the ground truth are in metres along a shape and no geometry number
reaches them; `run_many`'s fingerprint check is what enforces it. All three are
now swept (finding 13). They are worth 2 s of 166 between them: `cell=100` and
`octants=8` are already right, and `grid` wants to come down from 120 m to 45,
which is worth 2.3 s on `full` and is not yet confirmed on the stack.

**And the live service, `commuterlviv/live/`.** `commuterlviv serve` polls the vehicle
feed every five seconds, folds each fix into the same tracks the replay uses,
steps the model on the same 60 s grid, and pushes two things at the two rates
they actually change at: positions per poll, arrivals per epoch. It shares code
with the replay rather than resembling it - `Live.epoch` makes the same four
calls `replay._flush` makes - so the served numbers are the measured ones.

```sh
export COMMUTERLVIV_DATABASE_URL=postgresql://commuterlviv:...@127.0.0.1:55432/commuterlviv
export COMMUTERLVIV_ORIGINS=https://commuterlviv.r1a.nl,app://commuterlviv
python3 -m commuterlviv admin invite     # prints <web base>/join/<code>, once
python3 -m commuterlviv serve
```

Three design choices are worth knowing before reading it. Engine work runs in a
worker thread behind a lock and publishes frozen snapshots, because one epoch is
about 200 ms of numpy and a frame budget is 16 ms. Connections hold no send
queue: each diffs the published snapshot against what it last delivered, so a
slow client falls behind in time rather than in memory. And everything except
`/api/health` is behind a session, which the load measurement does not require -
it is there because an open socket streaming every vehicle in Lviv is a
scraper's dream. `/api/health` carries one thing that is not health,
`registration`, because both clients have to know whether to offer an invite
field, a sign-up button or neither, and they ask before anyone is signed in.

**And the web UI, `web/`.** React 19, Vite 7, TypeScript, Tailwind 4 - the
`newsense-web` stack without React Router, since one screen does not need
routing and `/join/<code>` is a regex in `App.tsx`.

```sh
cd web && npm install
npm run dev          # http://localhost:5173, proxying /api and /ws to :8099
npm run build        # dist/, 216 kB and 69 kB gzipped, plus lazy maplibre chunks
npm run preview      # http://localhost:5174, the built files with the same proxy
```

The proxy exists so the browser sees a single origin and the `__Host-` cookies
work in development exactly as they do in production. `COMMUTERLVIV_API` moves the
target if the service is not on 8099.

`public/sw.js` is the service worker, hand-written rather than generated: vite
hashes every asset name, so a precache list would have to be built, and caching
what has already been served reaches the same place after one visit. It is
registered only from a production build - the dev server has no `sw.js`, and a
worker holding the dev server's modules would serve them after they changed.
`deploy/Caddyfile` sends `Cache-Control: no-cache` for it, because a cached
worker outlives the deploy that replaced it.

The thing to understand before editing it is that **vehicle positions never
enter React**. `lib/live.ts` owns a `Map` of vehicles, the canvas loop in
`components/MapCanvas.tsx` reads that map sixty times a second, and React
subscribes through `useSyncExternalStore` to a small snapshot - connection,
arrivals, count - so a position frame re-renders nothing. Motion between the
five-second frames is interpolation, eased out over 1.2 s, with the heading
taking the short way round. Route badges are pre-rendered once per route into
offscreen canvases, so the draw loop blits instead of calling `fillText` four
hundred times a frame.

The city underneath is **MapLibre GL JS** over VersaTiles' OpenStreetMap vector
tiles - no key, no account, BSD and ODbL. Five styles are offered in the Routes
panel and the choice is kept in `localStorage`; `lib/theme.ts` holds them, and
holds the overlay's colours too, because a near-white vehicle nub reads on the
dark styles and disappears on the light ones. Switching is `map.setStyle`, so
the camera and the overlay survive it. `VITE_MAP_STYLE` still overrides
everything, for a self-hosted tile server. MapLibre owns every gesture and
the vehicles stay on a 2D canvas above it, drawn from MapLibre's own `render`
event and re-armed with `triggerRepaint()`, because an overlay on its own
animation frame reads the camera one frame late and the vehicles visibly slide
during a fling. `lib/geo.ts` repeats the Web Mercator formula MapLibre uses so
the draw loop does not call `map.project` once per vehicle per frame;
`check_web.py` asserts the two agree to half a pixel. Both the library and its
stylesheet are a dynamic import, so the sign-in screen never downloads them,
and its tile worker is bundled by Vite and handed over with `setWorkerUrl`.

**Two things the map deliberately refuses to claim**, both added on 2026-09-07
after the arrows were reported pointing sideways and backwards. The direction
arrow is no longer the feed's reported bearing - that field is gone from the
live path entirely, and only the collector still records it. It is the tangent
of the vehicle's own route shape at the position it has reached, averaged over
25 m either side, which is right by construction because arc position grows in
the direction of travel and is the same geometry the arrival times use. And the
marker only moves, or gets an arrow at all, when the tracker's speed clears the
stationary threshold by more than the tracker's own uncertainty about that
speed (`SURE = 1.0` sigmas in `live/state.py`); when it does, the map draws only
`DAMP = 0.7` of the dead-reckoned distance. The wire carries the verdict as flag
bit 1. **None of this touches `replay.believed`**, so the timetable's numbers
are still the ones the offline comparison measured - only the marker is held
back.

**And the phone app, `mobile/`.** Flutter, Android and iOS, the same client a
third time: no endpoint and no model of its own. It is Flutter rather than Expo
because it has to be publishable on F-Droid, which builds from source and takes
no proprietary SDK - so no Play Services, no Firebase, no keyed map SDK. The
basemap is the same VersaTiles tiles through `flutter_map` and
`vector_map_tiles`.

```sh
source /tmp/flutterenv.sh          # the toolchain, all under XDG paths
cd mobile && flutter pub get
flutter test                       # the wire decoder, against bytes wire.py made
flutter run --dart-define=COMMUTERLVIV_BASE=http://10.0.2.2:8099
flutter build apk --release        # unsigned unless android/key.properties exists
```

The structure mirrors the web app's for the same reason: every vehicle and stop
is one `CustomPaint` repainted from a `Ticker`, positions are eased between the
five-second frames, and each route's badge is laid out once into a
`ui.Paragraph`. `mobile/README.md` has the rest, including why the
locate-me button is a hand-written channel - AOSP's `LocationManager` on
Android, `CoreLocation` on iOS - and that the iOS half has never seen a
compiler, there being no Mac here. `mobile/fdroid/ua.lviv.commuterlviv.yml` is
the fdroiddata recipe and passes `fdroid lint`; what is left in it is the
owner's, and only the owner's - the `https://example.invalid` URLs, because
there is no public remote, and the `v0.5.0` tag it builds, because there are no
tags. `mobile/README.md` has the submission steps under "Getting it into
F-Droid".

**Five fixes on 2026-09-09, from a review of all three clients.** Pinned stops
now live on the server, in `user_prefs.data`, and are stored as **feed ids**
rather than catalog positions, so the phone and the browser finally agree about
what is pinned and a rebuilt catalog cannot shift a pin onto the next stop
along; `GET`/`POST /api/pins` is the whole surface, and each client migrates its
own `localStorage`/`SharedPreferences` key once and then drops it. The websocket
re-checks its session every 60 s (`app.py`'s `expire`) and closes with 4401 when
it has gone, so signing out on one device ends the socket on it rather than
leaving it fed until the tab is closed. A client's own message used to wake
every other client's push loop; each now has its own `asyncio.Event`. Client
messages are rated at 5 a second with a burst of 60 and the socket is closed
with 1008 after 500 refusals, and a frame over 16 KB is refused by uvicorn
before it is read. And the phone keeps its basemap: `mobile/lib/src/map_tiles.dart`
puts the tile cache under application support, 200 MB for 90 days.

**And a journey planner, 2026-09-09.** `GET /api/plan?from=lat,lon&to=lat,lon`
answers door to door - walk, ride, maybe change, walk - ranked by arrival, in
both clients (a third tab in the browser, the directions button on the phone).
It is a hand-rolled RAPTOR in `commuterlviv/plan.py` over an OpenStreetMap
walking graph in `commuterlviv/walk.py`, deliberately not OpenTripPlanner: one
process, no JVM, and the live model drops straight into it. There is no
hardcoded radius for nearby stops - the bound is the time to walk the whole way.
A tracked vehicle is fed in as a one-trip pattern of its own predictions, so
beyond the model's 45-minute horizon there are simply no live trips left and the
timetable takes over; every ride leg is labelled `live` or not, in both clients.
It needs two caches built once, `python -m commuterlviv walk` then `plan
--build`; without them the service still runs and `/api/plan` is a 503. How much
accuracy the far end of that horizon costs is unmeasured and waits on the VPS
recording.

**Versions, and where the APK lives, 2026-09-09.** The project has one version
number for all three trees, `0.2.0` as of this change: `commuterlviv/__init__.py`
is the source, `web/package.json`, `mobile/pubspec.yaml` and the F-Droid recipe
repeat it, `check.sh` fails if they drift, and `/api/health` reports it. Bump it
with every substantial change; it stays under 1.0 while this is alpha, and the
Android `versionCode` goes up with it because F-Droid orders by that alone.
`deploy/release-apk.sh` builds the phone app into `deploy/apk/`, which the web
container mounts read-only at `/srv/download`, so the newest build is always at
`<site>/download/commuterlviv.apk` - `http://10.8.0.2:8080/download/` over the
VPN. It replaces the `python3 -m http.server` that used to serve `/tmp/apk`,
which did not survive a reboot and served whatever was last copied there.

**Reaching the line, and saved places, 0.4.6 on 2026-09-11.** Every route badge
is now the way to that route's line - the stop card, the timetable, a ride in a
journey - in both clients. The one exception is the list that picks which routes
are on the map, where a tap already means something: there the line is on a long
press on the phone (`sheets.dart`) and on `onContextMenu` in the browser
(`RoutePanel.tsx`), which is one handler for both right-click and touch-hold.
Saved places - home, work - are the journey planner's ends, kept server-side in
`user_prefs.data` beside the pins, behind `GET`/`POST /api/places`, at most 24
and keyed by name, so saving over a name moves that place. The phone's route
sheet grew a stale-props bug fix worth remembering: `showFloatingSheet` puts the
sheet on its own route, built once, so the screen's later state never reaches it
- which is why the highlight used to stay on the previously chosen set. The
sheet keeps `_active` itself now, and can also update, rename and delete a set.
The own-location mark is a halo rather than a 6 px dot in both clients, because
a dot is the same mark as a stop and loses to forty vehicles around it.

## Do this next

0. **The recording is already merged.** `data/feed.db` is 3.98 days, three
   machines folded together by `commuterlviv merge`; `data/feed-host-early.db`
   is the old single-day file it superseded. So step 1 below no longer needs the
   download - only the scoring, which has not been run.
1. **Phase 6's first question, asked of Phase 5's answer.** Refit `stack-robust`
   on one day of `data/feed.db` and score it on the *next* one. Everything
   measured so far is fitted and used inside one recording, and the split
   already shows how
   much a night costs. This is the cheapest experiment that could invalidate
   finding 10, so it comes before anything that builds on it.
2. **Confirm `grid=45` on `stack-robust`** and change `network.DEFAULT` if it
   holds. It is the one geometry constant the sweeps found shipped wrong.
3. **Phase 7 is finished but has never been deployed to a real host.** It is
   packaged now - `docker compose up -d --build` is the whole of it, and Caddy
   in the stack does the history fallback and the single origin - but everything
   has only ever run on this machine. What a real host still needs is a domain
   in `COMMUTERLVIV_ORIGINS`, TLS in front or `docker-compose.tls.yml`, and a first
   `admin invite`.

Deviations from the plan's Phase 4 and 5 specs, all recorded in `PLAN.md`:

- Phase 5's one robustness idea became two rules, `stack-robust` (weights fitted
  under absolute loss) and `stack-median` (no weights at all), because "blending
  medians" can mean either and they defend against different failures.
- `debias` is not in the plan. It was added as a control once the fitted
  intercepts turned out to reach +122 s, so that the report can say how much of
  a blend's win is mixing predictors and how much is removing a shared bias.
- The hybrid uses `resid-quantile`, not the `resid-gbm` the plan names, because
  Phase 4 measured that the median-loss trees are the ones that separate.

- The plan lists `horizon` and `model_eta` as separate features. They are the
  same quantity - the predicted seconds to arrival - so only one is recorded.
- `fix_age` was added beyond the plan's list: how stale the believed position is
  when the prediction is made. It is causally available and obviously relevant.
- The midday split is not in the plan. It was added because the plan's split
  trains on 141 559 rows and tests on 2 757 685, so it measures transfer across
  a regime change and cannot say what a residual model is worth. Both are
  reported; neither is honest alone.

## Things that will cost you an hour if nobody tells you

- **An unsigned release APK says "App not installed" and nothing else.** The
  release is signed only if `mobile/android/key.properties` exists, so a fresh
  checkout builds an APK that installs nowhere; debug builds carry the debug
  key and install fine, which hides it. This machine's key is
  `mobile/android/commuterlviv-release.jks`, gitignored and not recoverable -
  lose it and every phone has to uninstall before it can update.
  `deploy/release-apk.sh` verifies the signature before publishing. Signing is
  v2-only past `minSdk` 24, so there is no `META-INF/*.RSA` to look for;
  `apksigner verify` is the only honest check.
- **Overpass answers 406 to a request with no `User-Agent`.** It is the Apache
  in front of it, not the API, and the body is an HTML error page that mentions
  nothing about the header - so it reads like a broken query. `walk.py` sends
  one. A 504 from the same endpoint is load; retry it.
- **`transfers.npz` is indexed against one catalog.** It numbers stops by
  `sorted(net.stops)`, so a copy taken from a host whose `network.pkl` differs
  is silently wrong. `walk.npz` is pure OSM and copies freely; that is why the
  container got the graph by `docker compose cp` and built the transfers itself.
- **MAE numbers are only comparable within one run.** Each run scores on the
  crossings every variant answered, and that support changes with the window and
  with the variant list. Seven different supports exist in the reports already,
  from 62 444 crossings in `stack-midday.md` to 115 264 in `residual.md`. Never compare a number across two runs;
  rerun both variants together instead.
- **`scikit-learn` 1.9.0 is installed** in the user site, and numpy 2.4.6 and
  pandas 2.3.3. There is no scipy and no torch. Keep sklearn an **optional
  extra and out of `requirements.txt`** - the collector runs on a small VPS and
  its footprint should not change.
- **The subcommand is `experiment`, singular.** `python3 -m commuterlviv` with no
  arguments prints all eleven.
- **There is no `sqlite3` command line tool** on this machine. Query the
  recording with `python3 -c` and the `sqlite3` module.
- **The city runs no service between roughly 00:00 and 05:30**, because of the
  war. A replay window inside that gap is empty by construction, and `replay.run`
  raises `NoData` saying so rather than failing obscurely.
- **Run `python3 check_parallel.py` after anything that touches `replay.py`.**
  It asserts the sequential and parallel replays track the same crossings in the
  same order. It takes about a minute.
- **The two live checks want a dev environment and fresh invite codes.**
  `python3 check_live.py <code> <code2>` registers `smoke_user` and expects
  `COMMUTERLVIV_DEV=true`, because under secure cookies the names it looks for are
  `__Host-` prefixed. `python3 check_web.py <code>` needs `npm run dev` up as
  well, registers a `browser_<timestamp>` account, and leaves screenshots in
  `/tmp/shot-*.png`. Both exit non-zero on a failure. Mint codes with
  `python3 -m commuterlviv admin invite`, one per registration. `check_live.py`
  registers the same username every time, so a second run against the same
  database fails with `that username is taken` and everything after it: clear
  it first with `admin delete smoke_user --yes`. It reads the base URL from
  `COMMUTERLVIV_CHECK_BASE`, not from an argument - both arguments are codes.
- **MapLibre's worker has to be handed to it, or neither dev nor the build
  draws a city.** Left alone it asks for `maplibre-gl-worker.mjs` beside its own
  module: pre-bundled by the dev optimiser that file is there but mute, and in
  the build it is a file rollup never emits, so the request 404s. Either way
  the style loads, `isStyleLoaded()` stays false, no tile is fetched and
  nothing is logged. `MapCanvas.tsx` imports the worker through Vite
  (`maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url`) and calls
  `setWorkerUrl` before creating the map; `worker: { format: "es" }` in the
  config is part of it, because MapLibre starts the worker as a module unless
  the url ends in `.cjs`.
- **The worker's requests never reach `performance.getEntriesByType`.** It
  fetches every tile, and it is a separate target, so `check_web.py` attaches
  to it with `Target.setAutoAttach` and counts `Network.requestWillBeSent`.
- **MapLibre's stylesheet sets `position: relative` on its container**, and it
  is imported after Tailwind, so a container held open by `inset-0` alone
  collapses and MapLibre falls back to its 400x300 default. `MapCanvas.tsx`
  uses `h-full w-full`. The symptom is subtle: the basemap renders, but the
  vehicles sit above their streets, because the overlay is full height and the
  map's transform is not.
- **Headless chromium needs `--enable-unsafe-swiftshader`** for the WebGL
  MapLibre requires, and then renders at about eight frames a second. Timing
  assertions in `check_web.py` wait for a change rather than comparing two
  frames a fixed interval apart.
- **The shell is zsh.** `grep --include=*.py` and unquoted `===MARKER===` both
  fail under it.
- **The live service needs an environment and a Postgres.** Every setting is
  `COMMUTERLVIV_*` and `settings.py` refuses to guess the two that matter:
  `COMMUTERLVIV_DATABASE_URL` and, unless `COMMUTERLVIV_DEV=true`, `COMMUTERLVIV_ORIGINS`.
  For development, `podman run -d --name commuterlviv-pg -e POSTGRES_PASSWORD=... -e
  POSTGRES_USER=commuterlviv -e POSTGRES_DB=commuterlviv -p 55432:5432
  docker.io/library/postgres:17-alpine` is what the smoke tests ran against.
  Migrations apply themselves at boot; there is no down direction.
- **`localhost:5173` and `127.0.0.1:5173` are different origins**, and the
  service is right to say `bad origin` when they disagree. Vite's dev server
  binds `localhost` only, so `COMMUTERLVIV_ORIGINS` has to contain the spelling the
  browser actually uses. Both are listed in the development environment, along
  with `http://localhost:5174` for `npm run preview`.
- **`web/src/lib/wire.ts` has to match `commuterlviv/live/wire.py` byte for byte.**
  Neither is derived from the other and a frame carries no box of its own, so
  changing one constant in one file moves every vehicle in the city. Check a
  change by encoding a frame in Python and decoding it in node - `npx esbuild
  src/lib/wire.ts --format=esm --outfile=/tmp/wire.mjs` is enough to import it.
- **And so does `mobile/lib/src/wire.dart`.** Three hand-written copies of one
  layout now. `mobile/test/wire_test.dart` decodes a frame Python encoded, so
  running `flutter test` catches a drift there; nothing catches a drift in
  `wire.ts` but `check_web.py`.
- **Caddy runs `try_files` in an earlier phase than `reverse_proxy`.** A block
  holding both rewrote `/api/health` to `/index.html` before the proxy's path
  matcher ever saw the path, so the API answered with the app's HTML and a 200 -
  no error anywhere. `deploy/Caddyfile` keeps the two in exclusive `handle`
  blocks. Any change to it wants `curl -s localhost:8080/api/health` afterwards,
  because the failure looks like success.
- **The compose project is pinned to `commuterlviv`**, in `docker-compose.yml`, so
  the volumes do not follow the worktree directory's name. The database this
  machine used before that lives in `main_postgres_data` and is now unused.
- **The feed is not a complete statement of which route serves which stop.**
  А16 calls at Енергетична (711), stop id `44236`: the line passes 12 m from
  the platform, and no А16 trip lists it - not in `stop_times.txt`, not in the
  city's own trip updates over a 0.95 GB recording, not on `api.lad.lviv.ua`'s
  board for that stop. Passing close is no evidence on its own: 738 route/stop
  pairs across the network are within 20 m of a line that does not serve them,
  which is what an opposite platform or a limited-stop pattern looks like. So
  additions are asserted by hand, one rule at a time, in
  `commuterlviv/overrides.toml`, and `python3 check_overrides.py` says whether
  each still applies.
- **An override needs a direction.** A rule without `toward` is added to every
  pattern whose line passes within 50 m, which on a two-way street is both
  platforms - and then riders waiting on the far side are told about vehicles
  going the other way. The platform at 711 is the 296° side; А16's two other
  patterns run 116° past it and must not get the stop - they get 712 instead,
  which is the same stop's other platform and was missing А16 for the same
  reason.
- **`flutter_map`'s gesture thresholds do nothing until the race is on.**
  `rotationThreshold`, `pinchZoomThreshold` and `pinchMoveThreshold` are only
  consulted by `_determineMultiFingerGestureWinner`, which never runs while
  `enableMultiFingerGestureRace` is false - the package's default. Off, every
  multi-finger gesture applies at once, so the twist a two-finger pinch always
  carries turns the map from the first degree; the reported symptom is a map
  that will not zoom without tilting. `mapInteraction` in
  `mobile/lib/src/map_controls.dart` turns the race on and widens rotation's
  win set to `MultiFingerGesture.all`, because the default
  (`MultiFingerGesture.rotate`) lets a won rotation lock zooming out until the
  fingers lift. When testing this, put the two pointers a hand's width apart:
  a twist moves each finger along a chord of half their separation, so at 50 px
  a 20° twist is 17 px of travel, under Flutter's own scale slop, and the
  gesture is never recognised at all - which looks exactly like a rotation
  threshold set far higher than it is.
- **A pickle carries the module path it was written from.** `data/network.pkl`
  is the city's geometry, pickled, so renaming the package to `commuterlviv`
  made the service die at startup with `ModuleNotFoundError: No module named
  'lvivpred'` - inside `network._load`, not anywhere near the rename. Move the
  file aside and the next start rebuilds it from the static feed in about a
  minute. `data/model.npz` is not affected: `state.py` loads it with
  `allow_pickle=False`, so it holds arrays and no class names.
- **Renaming the compose project renames the volumes with it.** The old data
  stays behind under the old prefix and the new stack comes up empty. Copy it
  first: `docker run --rm -v old_postgres_data:/from -v new_postgres_data:/to
  alpine sh -c 'cp -a /from/. /to/'`, and the same for `service_data`. The
  `lvivpred_*` volumes are still on this machine, holding the pre-rename copy.
- **Postgres reads `POSTGRES_USER` and `POSTGRES_DB` only when it initialises an
  empty cluster.** So `.env` still says `lvivpred` for both: the cluster on the
  volume was created with those names and nothing in the file can change them.
  Renaming them is two statements inside the database - `ALTER DATABASE lvivpred
  RENAME TO commuterlviv;` with nothing connected to it, then `ALTER ROLE`, which
  keeps the password because a scram verifier does not hash the role name.
- **An arrival's `t` is an absolute unix time, not a countdown.** The service
  sends when the vehicle calls; the client subtracts its own clock. Reading it
  the other way put "29814221 min" - unix seconds over sixty - on the phone.
  `web/src/lib/eta.ts` and `mobile/lib/src/eta.dart` are the same function on
  purpose, and `mobile/test/eta_test.dart` pins it.
- **A route's `type` is a word, not a GTFS number.** `gtfs.vehicle_type` reads
  `bus`, `tram` or `trolleybus` off the short name, and that is what
  `Catalog.describe` puts on the wire. Both clients had it typed as a number
  from the GTFS `route_type` codes, so the phone app crashed on the cast and the
  web app quietly coloured every tram and trolleybus as a bus - TypeScript never
  saw it, because the catalog is parsed and cast, not validated.
- **The emulator on this machine needs `-gpu swangle_indirect`**, and the app
  needs starting with `--ez enable-software-rendering true --ez
  enable-impeller false`. The default SwiftShader renderer segfaults the
  emulator process seconds after boot; SwANGLE survives the boot but the host
  `gfxstream` GLES2 decoder then takes a SIGILL on Flutter's first frame.
  `mobile/README.md` has the commands.
- **`vector_map_tiles` caches rendered tiles under the theme's id**, and every
  VersaTiles style parses to the id `default`. Switching the basemap style
  therefore changed the overlay colours and nothing else, on disk, for good.
  `home.dart`'s `_loadStyle` rebuilds the `Style` with
  `theme: read.theme.copyWith(id: theme.id)`.
- **`vector_map_tiles` caches its tiles in the temporary directory** unless
  `cacheFolder` says otherwise, and on Android that is the cache directory the
  system empties whenever it wants space. The symptom is a map that redownloads
  itself every few days for no reason anybody changed. `mobile/lib/src/map_tiles.dart`
  points it at application support instead.
- **`flutter analyze` resolves that package's `Directory` to its web stub**,
  where it is a `typedef Directory = String`, so passing a perfectly good
  `Future<Directory> Function()` to `cacheFolder` is an analyzer error and a
  compiler success - the compiler picks the `dart:io` branch of the conditional
  export. The `// ignore: argument_type_not_assignable` at that call is load
  bearing; `flutter build apk` is the check that matters.
- **`auth.load_session` refreshes the session's idle clock as a side effect.**
  Anything that only wants to *ask* whether a session is still alive - the
  websocket watchdog does - has to pass `touch=False`, or an open tab keeps
  itself signed in forever by being watched.
- **There is no `psql`** on this machine either. Query Postgres through
  `asyncpg`, or through `podman exec commuterlviv-pg psql`.
- **A restart starts the model cold unless the collector is recording locally.**
  `service.warm` replays the last two hours of `data/feed.db`, but only if the
  recording is less than 15 minutes old, which it is not while the collector
  lives on the VPS. Cold means roughly twenty minutes of the worst predictions
  the service ever makes.

## Layout

The checkout is worktree-style: `commuterlviv/` itself holds no files, only a bare
repository and one directory per branch. Work inside a branch directory - run
everything from `commuterlviv/main`, which is what every relative path in this
document means. Add a branch with `git -C commuterlviv worktree add <branch>`; each
gets its own `data/`, which is gitignored and rebuildable.

On this machine that root directory is still called `lvivpred/`: renaming it
means `git worktree repair` and every open shell losing its directory, so it was
left for whoever is not standing in it.

```
commuterlviv/
  .bare/  the repository itself, bare
  .git    a one-line pointer to .bare, so git works from the root too
  main/   the worktree for branch main; everything below is relative to it
```

```
commuterlviv/
  collect.py    poll the three feeds into data/feed.db, forever
  network.py    static GTFS -> shapes, stops, trips, patterns
  overrides.py / overrides.toml   stops the feed leaves off a route
  track.py      map-matching and the per-vehicle Kalman filter
  model.py      the estimator: cells, corridors, two half-lives, shrinkage
  baselines.py  the estimators that replace it: table, knn, median
  config.py     every approach, as a set of switches on one dataclass
  replay.py     walk the recording forwards, emit ETAs, collect features
  features.py   one feature row per emitted prediction
  residual.py   offline models of the model's own error, and their ablation
  stack.py      per-horizon blends of the predictors that fail differently
  walk.py       the city on foot: an OSM footpath graph, Dijkstra in seconds
  plan.py       RAPTOR over the timetable and the live vehicles, door to door
  truth.py      when each vehicle actually passed each stop
  predictors.py the four predictors reduced to one common form
  score.py      paired scoring on common support, with bootstrap intervals
  experiments.py / sweep.py / check.py / diag.py / evaluate.py / cli.py
  live/         the service: the model above, served
    settings.py   everything read from COMMUTERLVIV_*
    state.py      live tracks and the model, stepped on wall time
    wire.py       a map frame, 10 bytes a vehicle
    hub.py        one websocket per client, diffed rather than queued
    service.py    the poll and epoch loops
    db.py / migrations/   the pool and forward-only numbered SQL
    security.py   tokens, argon2, usernames, token buckets
    auth.py       sessions and remember-me, in Postgres
    prefs.py      named route sets and pinned stops, per account
    journeys.py   plan.py behind /api/plan, optional and 503 without its caches
    app.py        the HTTP and websocket surface
    admin.py      invite links, accounts, disabling one
web/            the UI: Vite, React 19, MapLibre with a canvas over it
  src/lib/      wire.ts (mirrors wire.py), live.ts (the socket and the
                vehicles), api.ts, geo.ts (Web Mercator, the same one
                MapLibre uses), sprites.ts (pre-rendered badges), eta.ts
  src/components/  MapCanvas (the basemap and the overlay), RoutePanel,
                StopCard, Timetable, JourneyPanel, SignIn
  src/App.tsx   the screen, the /join/<code> match, the pins
mobile/         the phone app: Flutter, Android and iOS, F-Droid-shaped
  lib/src/      wire.dart (mirrors wire.py), live.dart, api.dart,
                vehicle_layer.dart (one CustomPaint for the city),
                home.dart (the state both tabs share) and the widgets it
                hands to: map_tab, times_tab, stop_card, journey_panel,
                sheets, stop_search,
                map_theme.dart, strings.dart (uk and en)
  test/         wire_test.dart, against bytes Python encoded
  fdroid/       the fdroiddata build recipe; lint-clean, needs a public repo
  fastlane/     the store listing F-Droid reads from the repository
check.sh           everything checkable with nothing running: ruff's
                   will-it-run rules, the package imports, the web types and
                   build, flutter analyze and test. Run it before a commit
check_parallel.py  the replay-identity guard described above
check_prior.py     a one-off: is `tuned` just `no-prior` by another route
check_overrides.py every rule in overrides.toml, against a fresh build
check_live.py      37 assertions over a running service, from HTTP to the socket
check_web.py       the same for the UI, driving headless chromium over CDP
docker-compose.yml      db, service, collector, Caddy: the whole deployment
docker-compose.dev.yml  the overlay: source mounted, Vite instead of dist/
docker-compose.tls.yml  the overlay for when Caddy owns the domain
.env.example            every setting, with its default beside it
deploy/            service.Dockerfile, web.Dockerfile, Caddyfile, and a
                   systemd unit for a collector that runs outside containers
data/              the recording and the learned model; gitignored, rebuildable
```
