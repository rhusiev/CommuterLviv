#!/bin/sh
# A VersaTiles style, rewritten for this deployment. Every URL names this site
# rather than the public one, and every tile and glyph URL names the basemap's
# generation, so a new cut of the tiles is a new URL for every client. A client
# that holds an old tile under the old URL cannot be served it for the weeks
# the tile server allows a cache to keep it.
#
# A sprite URL carries no generation: MapLibre appends ".json" to its path and
# leaves a query alone, but the phone's tile reader appends to the whole string,
# query included, and would ask for "base?v=1.json".
#
# usage: style.sh <site-with-tiles-prefix> <generation> < public-style.json
set -eu

site=${1:?site with the /tiles prefix}
generation=${2:?basemap generation}
public=https://tiles.versatiles.org

sed -e "s#$public#$site#g" \
    -e "s#\(/tiles/tiles/[^\"]*\)\"#\1?v=$generation\"#g" \
    -e "s#\(/assets/glyphs/[^\"]*\)\"#\1?v=$generation\"#g"
