import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:commuterlviv/src/follow.dart' show Stage, StageKind;
import 'package:commuterlviv/src/followed.dart';
import 'package:commuterlviv/src/models.dart';

const tag = '"city-1"';
const arr = 10000;

final followed = Followed(
  journey: Journey(
    dep: 0,
    arr: arr,
    rides: 0,
    live: false,
    confidence: Confidence.live,
    legs: const [],
  ),
  to: const LatLng(49.84, 24.03),
  tag: tag,
);

String kept(Followed? f) => jsonEncode(f?.toJson());

void main() {
  test('is there after a restart, where it had got to', () {
    final raw = kept(followed.at(const Stage(StageKind.wait, 1)));

    final held = Followed.held(raw, tag, arr)!;

    expect(held.journey.arr, arr);
    expect(held.to, followed.to);
    expect(held.stage, const Stage(StageKind.wait, 1));
  });

  test('is gone once arrived', () {
    expect(followed.at(const Stage(StageKind.arrived, -1)), isNull);
  });

  test('is dropped on another catalog, whose positions it does not use', () {
    expect(Followed.held(kept(followed), '"city-2"', arr), isNull);
  });

  test('is dropped hours after it should have arrived', () {
    const hoursS = 3 * 3600;

    expect(Followed.held(kept(followed), tag, arr + hoursS), isNull);
  });
}
