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
| [reports/findings.md](reports/findings.md) | what the numbers turned out to mean. Thirteen findings, each with the measurement behind it |
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

## State of play, 2026-09-07

- **The collector now runs on the VPS, not on this machine.** The local one was
  stopped cleanly on 2026-09-06 18:56 when the repo was converted to the
  worktree layout below; its recording, `data/feed.db`, is 0.95 GB and covers
  2026-09-05 20:17 to 2026-09-06 18:56. Phase 6 is blocked until the recording
  covers three weekdays, so the VPS copy has to be pulled down and merged before
  that phase can start.
- **Phases 0-5 are done and scored.** `tuned` leads the approach comparison at
  114 s MAE, `full` (the shipped model) is at 120 s, the official API is far
  behind. Phase 4's residual models are scored on two splits and finding 9 says
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
  deployment has no certificate. The licence is MIT and the app defaults to `https://commuterlviv.r1a.nl`; the one
  thing still blocking an F-Droid submission is that the project has no public
  repository, so the recipe's URLs are placeholders.
- **The whole stack is now one command.** `docker compose up -d --build` brings
  up Postgres, the service, the collector and Caddy in front; the dev overlay
  swaps the built UI for Vite's dev server and opens the ports. Verified end to
  end against a scratch project, down to a websocket carrying frames. Guides for
  both are in `README.md`.

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
compiler, there being no Mac here. Two fields in `mobile/fdroid/ua.lviv.commuterlviv.yml` are the
owner's to fill: the licence, since the repository has no LICENCE file, and the
repository URL, since there is no remote.

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

## Do this next

1. **Phase 6's first question, asked of Phase 5's answer.** Pull the VPS
   recording down and merge it into `data/feed.db`, then refit `stack-robust` on
   one day and score it on the *next* one. Everything measured so far is fitted
   and used inside a single recording, and the plan's split already shows how
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
  fdroid/       the fdroiddata build recipe, two fields still TODO
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
