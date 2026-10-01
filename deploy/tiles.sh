#!/bin/sh
# The tiles container: keeps the basemap for Lviv on its volume and serves it,
# so no phone or browser asks tiles.versatiles.org for anything.
#
# Everything is fetched by the container itself, on the first start and again
# once it is REFRESH_DAYS old - the only traffic the public servers ever see
# from a deployment is this one machine, once a month:
#
#   lviv.versatiles     the extract, cut from the planet over range requests -
#                       only the bbox crosses the wire, about 20 MB
#   frontend.br.tar.gz  sprites and glyphs, from the versatiles-frontend release
#   static/assets/styles/<id>/style.json
#                       the styles, from the public server with its origin
#                       rewritten to this deployment's, because a style names
#                       its sprite, glyph and tile URLs absolutely
#
# A failed fetch keeps what is already there and is retried within the hour
set -u

site=${COMMUTERLVIV_WEB_BASE:-${COMMUTERLVIV_ORIGINS%%,*}}
site=${site%/}
public=https://tiles.versatiles.org
# Lviv and its approaches, from `walk.bbox(net)` - the same area the footpath
# graph covers, so the map has tiles exactly where the planner has streets
bbox=23.791,49.702,24.233,50.045
# The ids the clients offer, in web/src/lib/theme.ts and mobile/lib/src/map_theme.dart
styles="colorful colorful-dark natural natural-dark muted muted-dark gray gray-dark"
every=$(( ${REFRESH_DAYS:-30} * 86400 ))

cd /tiles || exit 1

stale() {
  [ ! -s "$1" ] || [ $(( $(date +%s) - $(stat -c %Y "$1") )) -ge "$every" ]
}

# Sets `changed` when the server has to be restarted to see a new file
refresh() {
  changed=
  if stale lviv.versatiles; then
    rm -f lviv.tmp.versatiles
    versatiles convert --bbox "$bbox" \
      https://download.versatiles.org/osm.versatiles lviv.tmp.versatiles \
      && mv lviv.tmp.versatiles lviv.versatiles && changed=1
  fi
  if stale frontend.br.tar.gz; then
    wget -qO frontend.tmp \
      https://github.com/versatiles-org/versatiles-frontend/releases/latest/download/frontend.br.tar.gz \
      && mv frontend.tmp frontend.br.tar.gz && changed=1
  fi
  # Styles are served from disk as they are, so they are swapped in whole and
  # need no restart. Also redone on a new site address, which they carry
  if stale static/assets/styles/colorful/style.json || [ "$(cat static/site 2>/dev/null)" != "$site" ]; then
    rm -rf static.new
    for id in $styles; do
      mkdir -p "static.new/assets/styles/$id"
      wget -qO- "$public/assets/styles/$id/style.json" \
        | sed "s#$public#$site/tiles#g" > "static.new/assets/styles/$id/style.json" \
        && [ -s "static.new/assets/styles/$id/style.json" ] || { rm -rf static.new; break; }
    done
    if [ -d static.new ]; then
      echo "$site" > static.new/site
      rm -rf static.old
      [ -d static ] && mv static static.old
      mv static.new static && rm -rf static.old
    fi
  fi
}

[ -n "$site" ] || { echo "COMMUTERLVIV_WEB_BASE or COMMUTERLVIV_ORIGINS must be set" >&2; exit 1; }

pid=
trap '[ -n "$pid" ] && kill "$pid"; exit 0' TERM INT

refresh
until [ -s lviv.versatiles ] && [ -s frontend.br.tar.gz ]; do
  echo "no basemap yet; retrying in an hour" >&2
  sleep 3600 & wait $!
  refresh
done

while :; do
  versatiles serve -s /tiles/static -s /tiles/frontend.br.tar.gz "[osm]/tiles/lviv.versatiles" &
  pid=$!
  changed=
  while [ -z "$changed" ] && kill -0 "$pid" 2>/dev/null; do
    sleep 3600 & wait $!
    refresh
  done
  kill "$pid" 2>/dev/null; wait "$pid"
done
