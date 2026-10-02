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
finds no syntax errors or undefined names, the package imports, the web app
typechecks and builds, and `flutter analyze` and `flutter test` pass. A missing
toolchain is reported and stepped over rather than failing the run.

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

The `places` release is not a version. `.github/workflows/places.yml` replaces
its `lviv-search.sqlite` on the 3rd of every month, and can be run by hand from
the Actions tab - see [search](service.md#search).

## Not committed

Notes for and from coding agents - `PLAN.md`, `HANDOFF.md`, `CLAUDE.md`,
`.claude/` - are gitignored. `data/` is everything downloaded or learned and is
gitignored too.
