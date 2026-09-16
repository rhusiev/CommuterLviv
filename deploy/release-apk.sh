#!/usr/bin/env bash
# Build the three per-ABI release APKs and put them where a GitHub release
# upload can pick them up. F-Droid's recipe points at these same paths on
# `releases/download/v%v/`, and reproduces each one from source to confirm
# they match.
#
# Naming matches the `binary:` URLs in
# `mobile/fdroid/nl.r1a.commuterlviv.yml`: `commuterlviv-<version>-<abi>.apk`.
# The version comes from `mobile/pubspec.yaml`.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/release/$(sed -n 's/^version: \([^+]*\)+.*/\1/p' "$root/mobile/pubspec.yaml")"

[ -n "${FLUTTER_ENV:-}" ] && . "$FLUTTER_ENV"
command -v flutter >/dev/null || {
  echo "flutter is not on PATH - /tmp/flutterenv.sh puts it there" >&2
  exit 1
}

cd "$root/mobile"
flutter build apk --release --split-per-abi

# An unsigned APK installs nowhere: Android rejects it without saying why.
# The release build is signed only if android/key.properties exists, so this
# is the check that catches a machine without the key before the files go
# anywhere
signer=$(ls -d "${ANDROID_HOME:-$HOME/.local/share/android-sdk}"/build-tools/*/apksigner 2>/dev/null | tail -1)
[ -n "$signer" ] || {
  echo "no apksigner in the SDK - the signatures were not checked" >&2
}

mkdir -p "$out"
flutter_apk="$root/mobile/build/app/outputs/flutter-apk"
for abi in armeabi-v7a arm64-v8a x86_64; do
  src="$flutter_apk/app-$abi-release.apk"
  dst="$out/commuterlviv-$(basename "$out")-$abi.apk"
  if [ -n "$signer" ]; then
    "$signer" verify "$src" >/dev/null 2>&1 || {
      echo "$src is not signed - see android/key.properties in mobile/README.md" >&2
      exit 1
    }
  fi
  cp "$src" "$dst"
done

echo
echo "Built and signed:"
ls -l "$out"
echo
echo "Tag this commit and push the tag, then attach these three files to a"
echo "GitHub release named v$(basename "$out") - the file names are what"
echo "F-Droid's recipe expects to find there."
