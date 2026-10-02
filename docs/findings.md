# Findings

Behaviour of things this repository does not control - the Android build
tools, fdroidserver and its CI, GitHub Actions, the city's feeds, browsers,
SQLite and the tile server - that cost time to work out and is not written down
where you would look for it. Each entry says what was observed, why it happens,
and what the code does about it.

## AGP re-serialises the merged manifest for every split after the first

**Observed.** F-Droid rebuilt v0.9.4 and verification failed on the arm64 APK
with `CHUNKED_SHA512 digest mismatch`, while the arm APK of the same pipeline
verified. `diff -rq` over the unzipped APKs showed exactly one differing file,
`AndroidManifest.xml`, same length (7240 bytes) on both sides. `aapt2 dump
xmltree` showed every element identical and every `line=` from `<application>`
onward larger by one on the GitHub Actions side: `application (line=47)` there,
`application (line=46)` in F-Droid's rebuild.

**Why.** The `line=` numbers come from the *merged* manifest that AGP generates,
not from `mobile/android/app/src/main/AndroidManifest.xml`. For a multi-split
build AGP's `ProcessMultiApkApplicationManifest` packages the merged manifest of
the first split verbatim and re-serialises it for every later split, and the
re-serialisation inserts a blank line before the `<!-- Backup is on by default
... -->` comment. So the per-split files under
`mobile/build/app/intermediates/packaged_manifests/release/processReleaseManifestForPackage/`
come out as:

- one `flutter build apk --release --split-per-abi` (all three ABIs):
  `armeabi-v7a` 132 lines, `arm64-v8a` 133, `x86_64` 133
- one `flutter build apk --release --split-per-abi --target-platform=<one>`:
  132 lines, whichever ABI it is

The old release workflow used the first form and the recipe uses the second, so
the workflow's arm APK matched F-Droid's rebuild by luck and the other two could
not.

**What the code does.** `.github/workflows/release.yml` and
`deploy/release-apk.sh` both loop over the three ABIs and run `flutter build`
once per ABI with `--target-platform`, so every APK is a first split. Three
sequential single-ABI builds in one working tree each produce the 132-line
manifest - no clean between them is needed.

## `libdartjni.so` carries a build-id derived from a randomised CMake path

**Observed.** F-Droid's rebuild and the GitHub Actions build differed only in the
20-byte GNU build-id note of `lib/<abi>/libdartjni.so`.

**Why.** AGP gives each build a random directory under the pub cache,
`<pub cache>/jni-1.0.3/android/.cxx/RelWithDebInfo/<random 8 chars>`, and that
path reaches the debug info of the pre-strip object. The build-id is hashed
before the strip, so stripping removes the path but keeps the hash that differs
because of it. Pinning `PUB_CACHE` does not help: the random segment is below it.

**What the code does.** `mobile/android/build.gradle.kts` hooks `doLast` on the
`strip*Release*` tasks and removes `.note.gnu.build-id` with `llvm-objcopy`.
Two caveats found the hard way: Gradle 9 has no `project.exec`, so the hook uses
`ProcessBuilder`; and `ndkDirectory` must be read inside `doLast`, because
reading it at configuration time forces NDK resolution before AGP has installed
the NDK and fails F-Droid's build with "NDK is not installed".

**The pub cache pin is now vestigial.** `PUB_CACHE=/tmp/pubcache` was added to
both sides before the build-id hook existed, but it only ever reached
fdroiddata's copy of the recipe as a comment - the copy F-Droid runs has no
such prefix. That accident is the proof the pin is unnecessary: F-Droid rebuilt
the arm APK with its default `%vagrant%/.pub-cache` and it matched, byte for
byte, a GitHub Actions APK built with `/tmp/pubcache`. The workflow still sets
it, only because moving it would change the reference APKs for no gain.

## Flutter's Gradle plugin installs its own NDK, not the one the recipe names

The recipe says `ndk: r27c` and the workflow passes `ndk-version: r27c`, but the
Flutter Gradle plugin demands and auto-installs NDK `28.2.13676358` (r28c) on
both sides - the build log says "Install NDK (Side by side) 28.2.13676358" and
`.note.android.ident` in the built `.so` files reads `r28c`. The two sides agree
because they agree on the plugin, not because of the `ndk:` line. Do not "fix"
that line to match without checking what the plugin actually resolves.

## fdroidserver runs the build phases inside `subdir`, not beside it

`prebuild:` and `build:` start in `build/<applicationId>/<subdir>` - for this app
`build/nl.r1a.commuterlviv/mobile`. `cd ..` there lands in the app directory
itself, not in its parent, so the Flutter template's `cd ..; mv <appid> ...`
dance fails with "No such file or directory". The recipe instead takes
`appdir=$(cd .. && pwd)` and moves `$appdir`.

## A `Summary:` line in the recipe fails fdroiddata's `tools check scripts`

fdroiddata moved summaries into `metadata/<applicationId>/en-US/summary.txt`
(commit `fbc050f8d` for this app). Its `make-summary-translatable.py` exits with
the *count of files it migrated*, so any non-zero count is a CI failure. Leaving
a `Summary:` in `metadata/nl.r1a.commuterlviv.yml` therefore breaks the job.
`mobile/fdroid/nl.r1a.commuterlviv.yml` keeps its `Summary:` because it is the
source of truth read by humans; the fdroiddata copy must not have one. That is
the one field in which the two copies are intentionally not identical, besides
comments and rewritemeta's field ordering.

## fdroiddata's fork CI builds every versionCode in one job

`fdroid build` in a fork pipeline loops over all three `Builds:` blocks in a
single job, and the buildserver provisioning leaves a real `~/.gitconfig`
behind, so the second iteration dies at `ln -s .../.gitconfig` with "File
exists". The fork branch's `.gitlab-ci.yml` uses `ln -sf`. This deviates from
upstream `fdroid/fdroiddata`, so keep it out of the merge request or upstream it
on its own.

## `checkupdates` takes only a strictly higher versionCode, from the five newest tags

`check_tags` in fdroidserver's `checkupdates.py` sorts the tags by commit date,
newest first, and keeps the first five. At each tag it reads the code and name
with `UpdateCheckData` and replaces its best only when `vercode > hcode`. So a
newer tag whose pubspec carries the code F-Droid has already built changes
nothing, however many of them there are - which is what makes a server-only
release with the app's version left behind safe.

## GitHub Actions spawns every step from `github.workspace`

The release workflow moves its checkout to `/tmp/build/nl.r1a.commuterlviv`, and
after that the runner fails to start any step - including the Node process of
`softprops/action-gh-release` - with "No such file or directory", because it
still spawns steps from the vanished `${{ github.workspace }}`. Two things about
the fix: `working-directory:` is not valid on a `uses:` step (it fails at 0s),
and an empty directory is enough, since the builds have already run. So a `run:`
step with its own `working-directory:` recreates the path with `mkdir -p
"$GITHUB_WORKSPACE"` before the release step.

## The live feed switches a vehicle's trip only at the first stop of the next

A vehicle that has reached its terminus keeps reporting the trip it finished,
while it stands and turns, and takes the next trip id only once it leaves that
trip's first stop. So a start stop such as tram 3's Аквапарк (519, 519-01) has
no vehicle "on" the trip about to depart, and a server that predicts only the
current trip shows nothing there. The GTFS `block_id` chains a vehicle's trips
in order, which is how the next trip is found

## Long press on Android WebView/Chrome arrives as `contextmenu`

maplibre has no long-press event. A touch held on the map fires the browser's
`contextmenu` event on Android, the same event a right click fires on desktop,
so one handler serves both

## A recording copied onto a spinning disk reads at seek speed

`feed.db` pulled from the server (23 GB) was written by appending over weeks, so
its pages are scattered. On the HDD the evaluation's random reads, and a full
`SELECT max(veh_ts) FROM veh`, stalled for tens of minutes. Reading the file
once sequentially (`cat feed.db > /dev/null`) and then `VACUUM INTO` a packed
copy makes the reads sequential again

## Lviv's GTFS splits the timetable by weekday in `calendar.txt`

The feed has separate services for weekdays, Saturday and Sunday (for example
service 31 runs weekdays with 8432 trips, service 224 Saturday and Sunday with
5340), and `calendar_dates.txt` is only a header. The `start_date` is the day
the feed is published. A planner that ignores `service_id` answers a Thursday
with weekend trips mixed in

## The Android emulator crashes when the app draws on the GPU

With the host GPU, `qemu-system-x86_64` dies of SIGILL (seen in `coredumpctl`)
as soon as the Flutter app renders. Starting the app with software rendering
keeps it alive: `adb shell am start -n nl.r1a.commuterlviv/.MainActivity --ez
enable-software-rendering true --ez enable-impeller false`

## A backdrop blur holds `position: fixed` children inside it

An element with `backdrop-filter` (Tailwind's `backdrop-blur-*`, part of the
web's `panel` utility) becomes the containing block for `fixed` descendants,
the same as a `transform` does. An `inset-0` overlay rendered inside the
journey panel covered only the panel. The backups dialog is portalled to
`document.body` for this

## `toLocaleTimeString` picks 12 or 24 hours from the browser's locale

`{ hour: "2-digit", minute: "2-digit" }` alone gives `08:01 AM` in an en-US
browser, which wraps in a 3rem clock column. The web's `clock` passes
`hourCycle: "h23"`, so it is always `HH:MM` like the mobile app

## A Material chip takes hits as a whole, not through its label

In a widget test, `longPress(find.text(...))` on a chip's label warns that the
offset "would not hit test on the specified widget": the chip's render object
answers the hit itself and never offers it to the label. The gesture still
lands on the chip, so the test passed with the warning. Aiming at the chip,
`find.widgetWithText(FilterChip, ...)`, is what the warning asks for

## scipy's Dijkstra keeps zero-weight edges given in a CSR matrix

**Observed.** `scipy.sparse.csgraph.dijkstra` on a `csr_matrix` holding an
explicit `0.0` edge walks it at no cost, and of two entries for the same edge
it uses the shorter; it neither drops the zero nor sums the pair. A dense input
would read a zero as no edge at all.

**Why.** For sparse input the matrix's stored entries are the edges, whatever
their value; only dense input goes through `csgraph_from_dense`, which treats
zero as missing.

**What the code does.** `Walk.reach` starts a search from many nodes by hanging
them off one extra node, with edges as long as the walk already spent reaching
each. A stop standing right on a node gives an edge of 0 s, which this relies
on. Sources are still deduplicated first, so nothing depends on the duplicate
rule.

## A numpy scalar in the profile scan's walking caps makes it half again slower

**Observed.** Once the walk-only time came from a numpy array (`seen[i] + t`
is an `np.float64`), the profile scan took 740 ms instead of 485 ms on the same
searches, with identical results.

**Why.** The time becomes the first walking cap, and the scan compares and
takes `min` of it against plain floats hundreds of thousands of times; every
such operation with an `np.float64` goes through numpy's scalar machinery.

**What the code does.** `_walk_through` turns the reading into a `float`.
`_connections` hands the scan its hops as plain lists (`.tolist()`) for the
same reason: one element at a time, a list and `bisect` beat numpy indexing and
`searchsorted` several times over.

## Terrarium elevation tiles: the decode, and what zoom 13 really holds

**Observed.** The tiles at
`https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png` are
256 px PNGs with no key and no rate limit we ran into. Lviv at zoom 13 is 120
tiles, about 80 s fetched one after another. The heights came out at 222-413 m,
the market square (Rynok) at 291 m. The median slope over a footpath edge is
2.3%, and 0.15% of edges are steeper than 30%.

**How a pixel decodes.** Height in metres is `R * 256 + G + B / 256 - 32768`,
from the red, green and blue bytes. There is no alpha meaning and no scale
factor per tile.

**What zoom 13 really holds.** A pixel there is about 12 m across at Lviv's
latitude (49.8°N), but the data under it is SRTM-class, about 30 m. Zooming in
further only interpolates the same data, so 13 is the coarsest zoom that loses
nothing. Sampling is bilinear between pixels, or short edges would see steps of
whole metres.

**Why the slope is clipped.** A 30 m terrain model smears a building, a
bridge or a cutting into a slope that the footpath does not climb. Past a rise
of 30% over the run (`STEEPEST`) the model is more likely wrong than the hill,
so steeper edges are walked as if at 30%.

## VersaTiles renamed its styles and the old URLs answer 301

**Observed.** `https://tiles.versatiles.org/assets/styles/shadow/style.json`
answers `301`, and so do `eclipse`, `graybeard` and `neutrino`. `curl -fs`
without `-L` takes the redirect's HTML body as the style.

**Why.** versatiles-style v6 renamed them: `eclipse` is `colorful-dark`,
`shadow` is `gray-dark`, `graybeard` is `gray`, `neutrino` is `muted`. The
release (`styles.tar.gz` on github.com/versatiles-org/versatiles-style) still
carries the old names as copies, but the server redirects. v6 also adds
`natural`, `natural-dark`, `muted-dark`, `toner` and `toner-dark`. Only the
`colorful`, `natural` and `muted` families colour parks and forests green;
`gray` and `gray-dark` - the old `graybeard` and `shadow` - are grey throughout.

**What the code does.** The clients offer the colorful, natural, muted and gray
families, light and dark, and read a saved old name as its successor
(`RENAMED` in `web/src/lib/theme.ts`, `_renamed` in `map_theme.dart`).
`deploy/tiles.sh` fetches the new names with busybox `wget`, which follows
redirects, and checks each file is not empty.

## The recording had no index on time

**Observed.** The service's warm-up took 24.6 s on the server's 35 GB
`feed.db` to replay two hours, and `SELECT max(veh_ts) FROM veh` alone took
minutes on a spinning disk.

**Why.** `veh` is a `WITHOUT ROWID` table keyed on `(veh_id, veh_ts)`. The key
orders rows by vehicle first, so neither `max(veh_ts)` nor `veh_ts >= ?` can use
it, and SQLite reads the whole table for both.

**What the code does.** `collect.SCHEMA` creates `veh_ts` on `veh(veh_ts)`. The
collector runs the schema on its first write, so an existing recording gets the
index the first time a new collector opens it.

## A conditional `fetch` skips the browser's HTTP cache, an unconditional one does not

**Observed.** The catalog was served with `max-age=86400`. A browser holding the
catalog in local storage always saw a new one after a feed change, but a
browser with empty local storage could be handed the previous day's catalog
from its HTTP cache - and then the socket's `hello` named another catalog, and
the page reloaded into the same cached answer.

**Why.** The Fetch standard turns a request's cache mode from `default` to
`no-store` when the page sets `If-None-Match` (or another conditional header)
itself, so `held()` in `web/src/lib/api.ts` reaches the server whenever it has
a tag to send. Without a tag the request is ordinary, and `max-age` lets the
browser answer it without asking.

**What the code does.** The catalog, shapes and streets are served
`Cache-Control: private, no-cache` with their ETag (`_held` in
`commuterlviv/live/app.py`), so every request revalidates and a 304 still costs
no body.

## Caddy's `header` adds to a proxied response's headers rather than replacing them

**Observed.** Tiles through the stack came with two `Cache-Control` headers:
`public, max-age=604800` from the Caddyfile and `public, max-age=2419200,
no-transform` from `versatiles serve`, which sets its own.

**Why.** `header` beside `reverse_proxy` is applied to the response before the
upstream's headers are copied in, so a header the upstream also sends ends up
twice. Conflicting `max-age` values leave each cache to pick one.

**What the code does.** The tiles block sets it with `header_down` inside
`reverse_proxy`, which rewrites the upstream's header in place.
