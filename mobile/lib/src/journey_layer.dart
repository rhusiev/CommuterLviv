/// The journey picked in the planner, drawn where it goes: walks dotted, rides
/// solid in the route's colour, one pill of times per stop.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'journey_tags.dart';
import 'map_theme.dart';
import 'models.dart';

class JourneyLayer extends StatelessWidget {
  const JourneyLayer({
    super.key,
    required this.journey,
    required this.catalog,
    required this.theme,
    required this.places,
  });

  final Journey journey;
  final Catalog catalog;
  final MapTheme theme;

  /// Saved places, whose names are printed beside their dots: a pill on one
  /// is lifted above it, clear of the name.
  final List<Place> places;

  @override
  Widget build(BuildContext context) {
    final ink = Palette.of(theme.dark);
    final legs = [
      for (final leg in journey.legs)
        if (leg.pts.length > 1) leg,
    ];
    final tags = [
      for (final tag in journeyTags(legs)) _Tag(tag.point, tag.text),
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
            for (final c in _clusters(tags))
              _stack(c, ink, lifted: _onPlace(c.first.point)),
          ],
        ),
      ],
    );
  }

  bool _onPlace(LatLng point) {
    const near = Distance();
    return places.any((place) => near(place.at, point) < sameStopM);
  }

  Color _colour(Leg leg, Palette ink) {
    final i = leg.route ?? -1;
    if (i < 0 || i >= catalog.routes.length) return ink.stop;
    final route = catalog.routes[i];
    return routeColour(route.short, route.type);
  }
}

/// One pill before placing: where it wants to sit and what it says.
class _Tag {
  const _Tag(this.point, this.text);

  final LatLng point;
  final String text;
}

/// Tags sharing one spot, as one marker: pills that would print over each
/// other are one stack instead. A pill is ~90x22, so 25 m merges what shares a
/// stop at every zoom while leaving apart what the map can separate.
List<List<_Tag>> _clusters(List<_Tag> tags) {
  const near = Distance();
  final out = <List<_Tag>>[];
  for (final tag in tags) {
    var placed = false;
    for (final c in out) {
      if (near(c.first.point, tag.point) < 25) {
        c.add(tag);
        placed = true;
        break;
      }
    }
    if (!placed) out.add([tag]);
  }
  return out;
}

/// A lifted stack's gap above its point: more than half a place's name plate,
/// which is drawn level with the place's dot.
const _lift = 10.0;

/// Centred on its point, or [lifted] to stand above it.
Marker _stack(List<_Tag> tags, Palette ink, {required bool lifted}) {
  final gap = lifted ? _lift : 0.0;
  return Marker(
    point: tags.first.point,
    width: 96,
    height: 22.0 * tags.length + 2.0 * (tags.length - 1) + gap,
    alignment: lifted ? Alignment.topCenter : Alignment.center,
    child: Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < tags.length; i++) ...[
              if (i > 0) const SizedBox(height: 2),
              _pill(tags[i], ink),
            ],
          ],
        ),
      ),
    ),
  );
}

Widget _pill(_Tag tag, Palette ink) => DecoratedBox(
  decoration: BoxDecoration(
    color: ink.nub,
    borderRadius: BorderRadius.circular(11),
    border: Border.all(color: ink.edge),
  ),
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    child: Text(
      tag.text,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        color: ink.edge,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    ),
  ),
);
