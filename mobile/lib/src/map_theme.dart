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

  String get styleUrl =>
      'https://tiles.versatiles.org/assets/styles/$id/style.json';
}

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
