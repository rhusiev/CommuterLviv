/// What a point nothing names is called: by the stop near it, else by where it
/// is - as the web calls it.
library;

import 'package:latlong2/latlong.dart';

import 'models.dart';
import 'stop_search.dart' show nearest;
import 'strings.dart';

/// The furthest a stop names a point by being near it, about four minutes'
/// walk. Chosen, not derived; the web uses the same.
const namesNearM = 300.0;

/// Decimals of a degree shown: 1e-4 is about 11 m.
const _degreeDecimals = 4;

/// The stop within [namesNearM] nearest [at], by its name without its code,
/// else the coordinates of [at].
String pointLabel(Catalog catalog, LatLng at) {
  if (nearest(catalog, at).firstOrNull case (final stop, final m)
      when m <= namesNearM) {
    return txt.nearStop(catalog.stops[stop].title.name);
  }
  return '${at.latitude.toStringAsFixed(_degreeDecimals)}, '
      '${at.longitude.toStringAsFixed(_degreeDecimals)}';
}
