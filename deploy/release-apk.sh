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

apk=build/app/outputs/flutter-apk/app-release.apk

# An unsigned APK installs nowhere: Android rejects it, and the phone says
# "App not installed" without saying why. The release is signed only if
# android/key.properties exists, so this is the check that catches a machine
# without the key before the file is published rather than after
signer=$(ls -d "${ANDROID_HOME:-$HOME/.local/share/android-sdk}"/build-tools/*/apksigner 2>/dev/null | tail -1)
if [ -n "$signer" ]; then
  "$signer" verify "$apk" >/dev/null 2>&1 || {
    echo "the build is not signed - see android/key.properties in mobile/README.md" >&2
    exit 1
  }
else
  echo "no apksigner in the SDK - the signature was not checked" >&2
fi

mkdir -p "$out"
cp "$apk" "$out/commuterlviv-$version.apk"
cp "$out/commuterlviv-$version.apk" "$out/commuterlviv.apk"
ls -l "$out"
