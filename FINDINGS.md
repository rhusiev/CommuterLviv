# Findings

Behaviour of things this repository does not control - the Android Gradle
plugin, Flutter's Gradle plugin, fdroidserver, fdroiddata's CI and GitHub
Actions - that cost time to work out and is not written down where you would
look for it. Each entry says what was observed, why it happens, and what the
code does about it.

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

## GitHub Actions spawns every step from `github.workspace`

The release workflow moves its checkout to `/tmp/build/nl.r1a.commuterlviv`, and
after that the runner fails to start any step - including the Node process of
`softprops/action-gh-release` - with "No such file or directory", because it
still spawns steps from the vanished `${{ github.workspace }}`. Two things about
the fix: `working-directory:` is not valid on a `uses:` step (it fails at 0s),
and an empty directory is enough, since the builds have already run. So a `run:`
step with its own `working-directory:` recreates the path with `mkdir -p
"$GITHUB_WORKSPACE"` before the release step.
