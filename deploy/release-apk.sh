#!/usr/bin/env bash
# Build the phone app and publish it where the stack serves it.
#
# The result lands in `deploy/apk/`, which the web container mounts at
# `/srv/download`, so the app is at `<site>/download/commuterlviv.apk` for a
# phone that cannot reach F-Droid. Both names are written: the versioned one so
# an older build is still there, and the stable one so a link keeps working.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/deploy/apk"

[ -n "${FLUTTER_ENV:-}" ] && . "$FLUTTER_ENV"
command -v flutter >/dev/null || {
  echo "flutter is not on PATH - /tmp/flutterenv.sh puts it there" >&2
  exit 1
}

version=$(sed -n 's/^version: \([^+]*\)+.*/\1/p' "$root/mobile/pubspec.yaml")
cd "$root/mobile"
flutter build apk --release

mkdir -p "$out"
cp build/app/outputs/flutter-apk/app-release.apk "$out/commuterlviv-$version.apk"
cp "$out/commuterlviv-$version.apk" "$out/commuterlviv.apk"
ls -l "$out"
