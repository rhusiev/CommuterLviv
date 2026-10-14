/// A journey being followed, kept across a restart until it is ended,
/// arrived or replaced. `web/src/lib/followed.ts` is the same.
library;

import 'dart:convert';

import 'package:latlong2/latlong.dart';

import 'follow.dart';
import 'models.dart';

/// Past its arrival by this much, a journey left followed is long over.
/// Chosen, not derived.
const _staleS = 2 * 3600;

/// The journey, where it goes, for searching again, and the catalog its stop
/// and route positions belong to
class Followed {
  const Followed({
    required this.journey,
    required this.to,
    required this.tag,
    this.stage,
  });

  factory Followed.fromJson(Map<String, dynamic> j) => Followed(
    journey: Journey.fromJson(j['journey'] as Map<String, dynamic>),
    to: LatLng(
      ((j['to'] as Map<String, dynamic>)['lat'] as num).toDouble(),
      ((j['to'] as Map<String, dynamic>)['lon'] as num).toDouble(),
    ),
    tag: j['tag'] as String,
    stage: j['stage'] == null
        ? null
        : Stage.fromJson(j['stage'] as Map<String, dynamic>),
  );

  final Journey journey;
  final LatLng to;
  final String tag;

  /// How far along it was, as the follower last said
  final Stage? stage;

  Map<String, Object?> toJson() => {
    'journey': journey.toJson(),
    'to': {'lat': to.latitude, 'lon': to.longitude},
    'tag': tag,
    'stage': stage?.toJson(),
  };

  /// Kept as [raw], unless the city has moved on to another catalog than
  /// [tag] or the journey is stale at [now], unix seconds
  static Followed? held(String? raw, String tag, int now) {
    if (raw == null) return null;
    final held = Followed.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    return held.tag == tag && held.journey.arr + _staleS > now ? held : null;
  }

  /// What to keep once the follower says [next]: null once arrived
  Followed? at(Stage next) => next.kind == StageKind.arrived
      ? null
      : Followed(journey: journey, to: to, tag: tag, stage: next);
}
