/// The last few things picked from a search, kept on this device only and
/// offered again before anything is typed. A stop by its feed id, so a new
/// catalog finds it again; a place by its name and point.
library;

import 'dart:convert';

import 'package:latlong2/latlong.dart';

/// As many as are offered: a short list read at a glance, not a history.
const searchedKept = 3;

class Searched {
  const Searched.stop(String this.stop) : name = null, at = null;
  const Searched.place(String this.name, LatLng this.at) : stop = null;

  /// Null when it is not one of its kind; null for what is not stored right
  static Searched? fromJson(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['stop'] case final String stop) return Searched.stop(stop);
      return Searched.place(
        j['name'] as String,
        LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
      );
    } on Object {
      return null;
    }
  }

  final String? stop;
  final String? name;
  final LatLng? at;

  String toJson() => jsonEncode(
    stop != null
        ? {'stop': stop}
        : {'name': name, 'lat': at!.latitude, 'lon': at!.longitude},
  );

  bool same(Searched other) => stop != null
      ? stop == other.stop
      : other.stop == null && name == other.name;
}

/// [picked] first, without its earlier copy, the oldest dropped past the cap.
List<Searched> withPicked(List<Searched> held, Searched picked) =>
    [picked, ...held.where((s) => !s.same(picked))].take(searchedKept).toList();
