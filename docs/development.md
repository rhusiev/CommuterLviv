# Development

## Branches

| branch | what it holds |
| --- | --- |
| `dev` | where every change lands, by push or by pull request |
| `main` | releases only. Protected: it takes nothing but merges of `dev`, through a pull request |
| `development-archive` | the research tree - the evaluation (`truth.py`, `predictors.py`, `score.py`, the `check_*.py` scripts), the reports and the experiments that never shipped. Not merged anywhere |

A release is `dev` merged into `main`. Deploy from `main`.

## Checks

```sh
./check.sh
```

It needs nothing but the checkout: the versions agree (see below), ruff
finds no syntax errors or undefined names, the package imports, the Python
tests pass, the web app typechecks, passes eslint and its tests and builds, and
`flutter analyze` and `flutter test` pass. A missing toolchain is reported and
stepped over rather than failing the run.

`.github/workflows/check.yml` runs it on every pull request and every push to
`dev`. There `CI` is set, and with it a missing toolchain fails the run, and so
does a skipped test: the browser tests drive the Chromium or Chrome the runner
image ships, and the database tests start their Postgres with its podman or
docker, so neither has a reason to skip.

## Tests

```sh
pip install -r requirements-dev.txt
python3 -m pytest
```

The Python tests run against a made-up city (`tests/city.py`): one bus line
of five stops along a straight road, built into a GTFS feed that the real
network build reads, and vehicles driven along it at a chosen speed. Because
the city is known exactly, the tests can say what the right answer is - when
a bus passes a stop, how long it stands, what a jammed road should teach the
model.

They cover the vehicle tracker, the layover rule and its learned model, the
offline replay, the live engine, the snapshot, and the HTTP and websocket API.
The API tests need Postgres. They use `COMMUTERLVIV_TEST_DATABASE_URL` if it is
set, and otherwise start a throwaway `postgres:16-alpine` container with podman
or docker. With neither, they are skipped. The live service they start runs on
the wall clock, in a time zone pinned so that it is noon there whatever the hour
(`tests/service.py` `isolate`): the city's timetable runs only in the morning.

`tests/browser_test.py` drives the built web app in headless Chromium:
`vite preview` serves `web/dist` and proxies to the service, which runs in the
test process on the made-up city. A user registers through the sign-in screen,
finds a stop and sees the bus on its board, and picks the route and sees the
bus on the map. Another boards the bus from its card, plans to a point picked
on the map, follows the journey and opens its list of steps. A link with `?stop=` or
`?route=` opens that stop or route. It needs `npm run build` first, and a Chromium -
`chromium-browser`, `chromium` or `google-chrome` on the PATH, or
`COMMUTERLVIV_TEST_CHROMIUM`. Playwright's own browser download is not needed.
Map tiles and fonts are blocked, so the map itself stays blank.

`npm test` in `web/` runs the web app's unit tests (vitest), each file with an
in-memory `localStorage` emptied before every test (`web/src/test/storage.ts`). Those of
`mobile/test` that test logic both apps share are ported line for line, so
the two implementations are checked against the same cases. The binary map frame is
checked across all three languages from one file, `tests/wire_frame.json`: the
server must encode its vehicles to its bytes, and both clients must decode the
bytes back to its vehicles - so a box, scale or flag that drifts in one of them
fails that one's tests. Name matching folds accents the same way: the web with
Unicode's NFKD, the app with a table written out by hand, since Dart has no NFKD.
`tests/fold_cases.json` holds what NFKD folds each Latin and Cyrillic letter to,
`tests/fold_test.py` keeps it equal to Python's NFKD (and rewrites it when run as
`python3 -m tests.fold_test`), and both clients check every case.

## The version

**One version line, which the app follows when it changes.**
`commuterlviv/__init__.py` holds the version and `web/package.json` repeats it,
because the web app ships with the server. The service reports it at
`/api/health`, so what is deployed is a question with an answer. It goes up with
every substantial change and stays under 1.0 while this is alpha.

`mobile/pubspec.yaml` and the F-Droid recipe carry the app's version. It is
bumped to the same number only when the app changed, and the Android
`versionCode` (the `+N` in the pubspec) goes up with it, because F-Droid orders
releases by that alone. Otherwise the app stays at the version of its last
release: a server fix does not make every phone download an identical app.
`check.sh` fails if the web app and the server drift apart, if the recipe and
the pubspec drift apart, or if the app gets ahead of the server.

## Releases

Releases are made by `.github/workflows/release.yml`, never by hand and never
from `dev`:

1. A pull request from `dev` is merged into `main`. The push to `main` starts
   the workflow.
2. It reads the version from `commuterlviv/__init__.py` and asks the remote
   whether `v<version>` is already a tag. If it is, the merge carried no new
   version and nothing is released.
3. If the pubspec carries the same version, it builds the three per-ABI APKs
   the way F-Droid does, signs them and verifies the signatures. Only then does
   it create the annotated tag `v<version>` on the merged commit and push it,
   and publish a GitHub release with the APKs attached.
4. If the pubspec is behind, the release is the server's and the web app's
   alone. The workflow first checks that nothing under `mobile/` but the recipe
   and its README changed since the app's own tag. If something did, the run
   fails, because the app needed a version too. Otherwise it tags the commit
   and publishes a release with no APKs. That release is not marked latest, so
   the releases page keeps pointing at the newest APKs.
5. F-Droid's recipe (`mobile/fdroid/nl.r1a.commuterlviv.yml`) watches tags
   (`UpdateCheckMode: Tags`). It reads the versionCode from the pubspec at each
   tag and builds only a code higher than it has. A server-only tag carries the
   code F-Droid already has, so it is passed over. For a new code, F-Droid builds
   the tag from source, downloads the APKs from the release and publishes only
   if the bytes match.

So bumping the version on `dev` is what asks for a release, and merging it is
what makes one. Bumping the pubspec as well is what makes it an app release.
`deploy/release-apk.sh` builds the same APKs locally, for checking
reproducibility before a merge; it publishes nothing.

A pre-release is a build of `dev` for testing before a release:
`.github/workflows/prerelease.yml` runs on a pushed `dev-*` tag on `dev`, builds
and signs the same APKs through the action `release.yml` uses
(`.github/actions/apks`), and publishes them as a GitHub pre-release. It refuses
a pubspec version no `v<app>` release has shipped, since F-Droid would build
that tag; so the app keeps its released version and installs over it. It
deploys nothing - the server and web app of that commit run where you put them.
`.github/workflows/prune-prereleases.yml` deletes a pre-release and its tag once
a `v*` release includes its commit, or once it is 14 days old unless it is the
newest. It runs daily and after each release, from `main` only.

The `places` release is not a version. `.github/workflows/places.yml` replaces
its `lviv-search.sqlite` on the 3rd of every month, and can be run by hand from
the Actions tab - see [search](service.md#search).

## Not committed

Notes for and from coding agents - `PLAN.md`, `HANDOFF.md`, `CLAUDE.md`,
`.claude/` - are gitignored. `data/` is everything downloaded or learned and is
gitignored too.
