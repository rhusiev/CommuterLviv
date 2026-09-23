/// The journey picked in the planner, drawn where it goes: walks dotted, rides
/// solid in the route's colour, each leg labelled with how long it takes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'eta.dart';
import 'map_theme.dart';
import 'models.dart';
import 'strings.dart';

class JourneyLayer extends StatelessWidget {
  const JourneyLayer({
    super.key,
    required this.journey,
    required this.catalog,
    required this.theme,
  });

  final Journey journey;
  final Catalog catalog;
  final MapTheme theme;

  @override
  Widget build(BuildContext context) {
    final ink = Palette.of(theme.dark);
    final legs = [
      for (final leg in journey.legs)
        if (leg.pts.length > 1) leg,
    ];
    return Stack(
      children: [
        PolylineLayer(
          polylines: [
            for (final leg in legs)
              leg.walking
                  ? Polyline(
                      points: leg.pts,
                      color: ink.stop,
                      strokeWidth: 4,
                      pattern: const StrokePattern.dotted(),
                    )
                  : Polyline(
                      points: leg.pts,
                      color: _colour(leg, ink),
                      strokeWidth: 5,
                      borderColor: ink.edge,
                      borderStrokeWidth: 1.5,
                    ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final leg in legs) ...[
              _label(
                leg.pts[leg.pts.length ~/ 2],
                txt.minutes(spanMinutes(leg.arr - leg.dep)),
                ink,
              ),
              if (!leg.walking) ...[
                _label(leg.pts.first, clockTime(leg.dep), ink, bold: true),
                _label(leg.pts.last, clockTime(leg.arr), ink, bold: true),
              ],
            ],
          ],
        ),
      ],
    );
  }

  Color _colour(Leg leg, Palette ink) {
    final i = leg.route ?? -1;
    if (i < 0 || i >= catalog.routes.length) return ink.stop;
    final route = catalog.routes[i];
    return routeColour(route.short, route.type);
  }
}

Marker _label(LatLng at, String text, Palette ink, {bool bold = false}) =>
    Marker(
      point: at,
      width: 64,
      height: 22,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ink.nub,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: ink.edge),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(
              text,
              style: TextStyle(
                color: ink.edge,
                fontSize: 11,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
