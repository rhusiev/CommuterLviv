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

It needs nothing but the checkout: the version agrees across three trees, ruff
finds no syntax errors or undefined names, the package imports, the web app
typechecks and builds, and `flutter analyze` and `flutter test` pass. A missing
toolchain is reported and stepped over rather than failing the run.

## The version

**One version, three trees.** `commuterlviv/__init__.py` holds it,
`web/package.json` and `mobile/pubspec.yaml` repeat it, and `check.sh` fails if
they drift; the service reports it at `/api/health`, so what is deployed is a
question with an answer. It goes up with every substantial change and stays
under 1.0 while this is alpha - and the Android `versionCode` (the `+N` in the
pubspec) goes up with it, because F-Droid orders releases by that alone.

## Releases

Releases are made by `.github/workflows/release.yml`, never by hand and never
from `dev`:

1. A pull request from `dev` is merged into `main`. The push to `main` starts
   the workflow.
2. It reads the version from `commuterlviv/__init__.py` and asks the remote
   whether `v<version>` is already a tag. If it is, the merge carried no new
   version and nothing is released.
3. Otherwise it builds the three per-ABI APKs the way F-Droid does, signs them
   and verifies the signatures.
4. Only then does it create the annotated tag `v<version>` on the merged commit
   and push it, and publish a GitHub release with the APKs attached.
5. F-Droid's recipe (`mobile/fdroid/nl.r1a.commuterlviv.yml`) watches tags
   (`UpdateCheckMode: Tags`). It builds the tag from source, downloads the APKs
   from the release and publishes only if the bytes match.

So bumping the version on `dev` is what asks for a release, and merging it is
what makes one. `deploy/release-apk.sh` builds the same APKs locally, for
checking reproducibility before a merge; it publishes nothing.

## Not committed

Notes for and from coding agents - `PLAN.md`, `HANDOFF.md`, `CLAUDE.md`,
`.claude/` - are gitignored. `data/` is everything downloaded or learned and is
gitignored too.
