/// The basemap's look, and the colours the vehicle overlay is drawn in. The
/// overlay is painted above the map, so every one of its colours comes from
/// the chosen style's [dark] flag.
library;

import 'package:flutter/material.dart';

class MapTheme {
  const MapTheme(this.id, this.name, {required this.dark});

  final String id;
  final String name;
  final bool dark;

  String get styleUrl => '$_tiles/assets/styles/$id/style.json';
}

/// Where the basemap comes from: the public server unless `/api/health` says
/// the deployment serves its own. Nothing is compiled in.
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

/// The number without the city's kind letter: `А25` bus, `Т07` tram, `Тр33`
/// trolleybus.
String routeNumber(String short) => short
    .replaceFirst(RegExp(r'^(Тр|Т|А)'), '')
    .replaceFirst(RegExp(r'^0+(?=.)'), '');

/// One hue per route short name; trolleybuses and trams cooler, buses warmer.
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
