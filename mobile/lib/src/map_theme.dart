/// The basemap's look, and the colours the vehicle overlay is drawn in.
///
/// VersaTiles serves five styles of OpenStreetMap at one URL shape, over the
/// same tiles. `dark` is not decoration: the vehicles and stops are painted
/// above the map, and a near-white marker that reads perfectly on `shadow`
/// disappears on `neutrino`, so every overlay colour is picked from here.
/// Mirrors `web/src/lib/theme.ts`.
library;

import 'package:flutter/material.dart';

class MapTheme {
  const MapTheme(this.id, this.name, {required this.dark});

  final String id;
  final String name;
  final bool dark;

  String get styleUrl => '$_tiles/assets/styles/$id/style.json';
}

/// Where the basemap comes from. The public server unless the deployment this
/// app is pointed at serves its own, which `/api/health` says and `Api.health`
/// records. Nothing here is compiled in: the app carries no tile host, so one
/// build works against any deployment and following a different server means
/// following its map too.
String _tiles = _public;
const _public = 'https://tiles.versatiles.org';

void setTileOrigin(String? origin) => _tiles = origin ?? _public;

const mapThemes = [
  MapTheme('shadow', 'Shadow', dark: true),
  MapTheme('eclipse', 'Eclipse', dark: true),
  MapTheme('graybeard', 'Graybeard', dark: false),
  MapTheme('neutrino', 'Neutrino', dark: false),
  MapTheme('colorful', 'Colorful', dark: false),
];

MapTheme themeById(String? id) =>
    mapThemes.firstWhere((t) => t.id == id, orElse: () => mapThemes.first);

/// What the overlay paints with, over a basemap of this brightness
class Palette {
  const Palette({
    required this.stop,
    required this.edge,
    required this.nub,
    required this.here,
  });

  factory Palette.of(bool dark) => dark
      ? const Palette(
          stop: Color(0xffcfd8e3),
          edge: Color(0xff0b0f14),
          nub: Color(0xffe8eef7),
          here: Color(0xff38bdf8),
        )
      : const Palette(
          stop: Color(0xff334155),
          edge: Color(0xfff8fafc),
          nub: Color(0xff1e293b),
          here: Color(0xff0284c7),
        );

  final Color stop;
  final Color edge;
  final Color nub;
  final Color here;
}

/// The number without the letter the city puts in front of it: `А25` is a bus,
/// `Т07` a tram, `Тр33` a trolleybus. `web/src/lib/sprites.ts` does the same,
/// so a badge says the same thing in both clients.
String routeNumber(String short) => short
    .replaceFirst(RegExp(r'^(Тр|Т|А)'), '')
    .replaceFirst(RegExp(r'^0+(?=.)'), '');

/// One hue per route short name, so two neighbouring routes are never the same
/// circle. Trolleybuses and trams read as cooler, buses warmer. The arithmetic
/// is `web/src/lib/sprites.ts` exactly, so a route is the same colour in both.
Color routeColour(String short, String type) {
  var h = 0;
  for (final unit in short.codeUnits) {
    h = (h * 31 + unit) % 360;
  }
  final base = type == 'tram' ? 200 : (type == 'trolleybus' ? 260 : 20);
  return HSLColor.fromAHSL(
    1,
    ((base + h % 90) % 360).toDouble(),
    0.70,
    0.52,
  ).toColor();
}
