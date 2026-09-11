#!/usr/bin/env bash
# Put together everything `docker-compose.tiles.yml` needs to serve the basemap,
# so no phone or browser ever talks to tiles.versatiles.org.
#
#   deploy/tiles-setup.sh https://commuterlviv.example.org [dir]
#
# The address is this deployment's own, and the only place it is written down.
# It ends up inside the style files, which is why they are generated here rather
# than committed: a style names its sprite, glyph and tile URLs absolutely, and
# a checked-in copy would name whoever generated it.
#
# Re-runnable. The extract is the slow part and is kept if it is already there;
# delete it to re-cut, which is what a new bbox or a newer planet needs.
set -eu

site=${1:?usage: tiles-setup.sh <https://site> [dir]}
site=${site%/}
dir=${2:-tiles}

# Lviv and its approaches, from `walk.bbox(net)` - the same area the footpath
# graph covers, so the map has tiles exactly where the planner has streets
bbox=23.791,49.702,24.233,50.045

mkdir -p "$dir/static/assets/styles"
cd "$dir"

if [ ! -f lviv.versatiles ]; then
  # `convert` reads the 66 GB planet over HTTP range requests, so only the bbox
  # crosses the wire - about 20 MB at maxzoom 14, not 66 GB
  versatiles convert --bbox "$bbox" \
    https://download.versatiles.org/osm.versatiles lviv.versatiles
fi

[ -f frontend.br.tar.gz ] || curl -fLo frontend.br.tar.gz \
  https://github.com/versatiles-org/versatiles-frontend/releases/latest/download/frontend.br.tar.gz

# Frontend v3.14 builds `style.json` in the browser and no longer ships the
# files, so they are taken from the public server and repointed here. Written
# through a temporary file: a half-downloaded style is still valid JSON as far
# as the server is concerned, and serves a map with no sprites
for id in shadow eclipse graybeard neutrino colorful; do
  mkdir -p "static/assets/styles/$id"
  curl -fs "https://tiles.versatiles.org/assets/styles/$id/style.json" \
    | sed "s#https://tiles\.versatiles\.org#$site/tiles#g" \
    > "static/assets/styles/$id/style.json.tmp"
  mv "static/assets/styles/$id/style.json.tmp" "static/assets/styles/$id/style.json"
done

echo "ready in $(pwd) - set COMMUTERLVIV_TILES to it and bring the stack up"
echo "  docker compose -f docker-compose.yml -f docker-compose.tiles.yml up -d"
