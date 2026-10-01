/// The journey picked in the planner, drawn where it goes: walks dotted, rides
/// solid in the route's colour, one pill of times per stop.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'eta.dart';
import 'map_theme.dart';
import 'models.dart';

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
    // Timestamps only, one pill per stop; durations stay in the planner's
    // list. A third and further time on one spot joins the stack.
    final groups = <_Group>[];
    for (final leg in legs) {
      _at(groups, leg.pts.first).on.add(leg.dep);
      _at(groups, leg.pts.last).off.add(leg.arr);
    }
    final tags = <_Tag>[
      for (final g in groups) ...[
        _Tag(g.point, g.text, true),
        for (final extra in g.extras) _Tag(g.point, clockTime(extra), true),
      ],
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
        MarkerLayer(markers: [for (final c in _clusters(tags)) _stack(c, ink)]),
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

/// One stop's worth of times: every alighting and boarding within 25 m, which
/// is one stop at every zoom. [text] reads off → on for a change, or the one
/// time when there is only it; [extras] holds a third and further time, which
/// the stack draws as its own pill on the same spot.
class _Group {
  _Group(this.point);

  final LatLng point;
  final List<int> off = [];
  final List<int> on = [];

  String get text {
    if (off.isNotEmpty && on.isNotEmpty && off.last != on.first) {
      return '${clockTime(off.last)} → ${clockTime(on.first)}';
    }
    return clockTime(off.isNotEmpty ? off.last : on.first);
  }

  Iterable<int> get extras sync* {
    for (var i = 0; i + 1 < off.length; i++) {
      yield off[i];
    }
    for (var i = 1; i < on.length; i++) {
      yield on[i];
    }
  }
}

/// The group [at] belongs to, opening one when it stands alone.
_Group _at(List<_Group> groups, LatLng at) {
  const near = Distance();
  for (final g in groups) {
    if (near(g.point, at) < 25) return g;
  }
  final opened = _Group(at);
  groups.add(opened);
  return opened;
}

/// One pill before placing: where it wants to sit, what it says, how loudly.
class _Tag {
  const _Tag(this.point, this.text, this.bold);

  final LatLng point;
  final String text;
  final bool bold;
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

Marker _stack(List<_Tag> tags, Palette ink) => Marker(
  point: tags.first.point,
  width: 96,
  height: 22.0 * tags.length + 2.0 * (tags.length - 1),
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
);

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
        fontWeight: tag.bold ? FontWeight.bold : FontWeight.normal,
      ),
    ),
  ),
);
