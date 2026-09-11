#!/usr/bin/env bash
# Redraw every icon of all three clients from the one mark.
#
# `web/public/icon.svg` is the master and the only place the shape is defined;
# everything below is that file at a different size, or with one element
# removed. Run it after changing the mark, and commit what it writes: a build
# from source - F-Droid's, or anyone's - must not need a rasteriser.
#
#   tool/icons.sh
#
# The cuts, and why each is different:
#
#   Android legacy   the whole mark, rounded corners and all, one PNG per
#                    density. What Android 7 and older show.
#   Android adaptive the mark with no background, on a canvas 1.64x its size.
#                    The launcher animates and masks the icon, and only the
#                    middle 66 of 108 units is guaranteed to survive; a mark
#                    drawn to the edge loses its edges. The background is a
#                    flat colour, which is what makes the parallax look right.
#   Android splash   the mark alone at 96dp, drawn centred over that same
#                    colour by drawable/launch_background.xml.
#   iOS              square, never rounded and never transparent - iOS applies
#                    its own mask, and an alpha channel is rejected outright by
#                    App Store validation.
#   Web              the plain mark for a home-screen shortcut, plus a
#                    `maskable` one framed like the Android adaptive icon,
#                    because a browser crops that one to whatever shape the
#                    platform uses.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
src="$root/web/public/icon.svg"
res="$root/mobile/android/app/src/main/res"
ios="$root/mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset"
web="$root/web/public"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

command -v rsvg-convert >/dev/null || {
  echo "rsvg-convert is not installed (librsvg2-tools)" >&2
  exit 1
}

# The mark alone, in two framings. Drop the plate and what is left spans
# x 153..359 and y 109..477 - 368 units tall, centred on (256, 293), not on the
# middle of the original box.
#
# Adaptive: that 368 has to land on the 66 of the 108-unit canvas that survives
# every launcher mask, so the canvas is 368 * 108 / 66 = 602 units square,
# centred on the mark: 256-301 = -45, 293-301 = -8.
#
# Splash: the smallest square around the mark, 410 units, same centre.
mark=$(sed '/<rect/d' "$src")
echo "$mark" | sed 's|viewBox="0 0 512 512"|viewBox="-45 -8 602 602"|' > "$tmp/fg.svg"
echo "$mark" | sed 's|viewBox="0 0 512 512"|viewBox="51 88 410 410"|' > "$tmp/splash.svg"
sed 's/rx="96"//' "$src" > "$tmp/square.svg"

png() {          # png <svg> <size> <out>
  rsvg-convert -w "$2" -h "$2" "$1" -o "$3"
}

echo "android"
set -- mdpi 48 hdpi 72 xhdpi 96 xxhdpi 144 xxxhdpi 192
while [ $# -gt 0 ]; do
  mkdir -p "$res/mipmap-$1" "$res/drawable-$1"
  png "$src" "$2" "$res/mipmap-$1/ic_launcher.png"
  # 108 units where the legacy icon is 48: the adaptive canvas is 2.25x
  png "$tmp/fg.svg" "$(($2 * 9 / 4))" "$res/mipmap-$1/ic_launcher_foreground.png"
  # The splash mark is 96dp, twice the legacy icon
  png "$tmp/splash.svg" "$(($2 * 2))" "$res/drawable-$1/splash.png"
  shift 2
done

echo "ios"
python3 - "$ios" "$tmp/square.svg" <<'EOF'
import json
import pathlib
import subprocess
import sys

from PIL import Image

out, svg = pathlib.Path(sys.argv[1]), sys.argv[2]
for image in json.loads((out / "Contents.json").read_text())["images"]:
    px = round(float(image["size"].split("x")[0]) * float(image["scale"].rstrip("x")))
    at = out / image["filename"]
    subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), svg,
                    "-o", str(at)], check=True)
    # rsvg always writes RGBA, and an alpha channel - even a fully opaque one -
    # is what App Store validation rejects
    Image.open(at).convert("RGB").save(at)
    print(f"  {image['filename']} {px}px")
EOF

echo "web"
for size in 192 512; do
  png "$src" "$size" "$web/icon-$size.png"
done
# The same framing as the adaptive icon, over the plate, because a maskable
# icon is cropped by the platform and only its middle survives
sed 's|viewBox="0 0 512 512"|viewBox="-45 -8 602 602"|' "$tmp/square.svg" \
  | sed 's|<rect width="512" height="512"|<rect x="-45" y="-8" width="602" height="602"|' \
  > "$tmp/maskable.svg"
png "$tmp/maskable.svg" 512 "$web/icon-maskable.png"

echo "done - commit the PNGs"
