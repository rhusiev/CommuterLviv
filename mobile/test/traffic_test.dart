import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/traffic.dart';

/// The most a coordinate may move when a path or a canvas transform holds it
/// as a 32-bit float, in pixels at the zoom it is projected at
const _f32ToleratedPx = 0.01;

double _asF32(double v) => (Float32List(1)..[0] = v)[0];

void main() {
  test('a stretch with too little seen on it is drawn as nothing', () {
    expect(trafficColour(null), isNull);
  });

  test('the ramp runs from free-flowing to a crawl', () {
    expect(trafficColour(0.2), trafficRamp.first.$2);
    expect(trafficColour(0.85), trafficRamp.first.$2);
    expect(trafficColour(1.6), trafficRamp.last.$2);
    expect(trafficColour(3), trafficRamp.last.$2);
  });

  test('between two stops the colour is mixed', () {
    final middle = trafficColour(0.925)!;
    final half = Color.lerp(
      trafficRamp[0].$2,
      trafficRamp[1].$2,
      (0.925 - trafficRamp[0].$1) / (trafficRamp[1].$1 - trafficRamp[0].$1),
    )!;
    expect(middle.toARGB32(), half.toARGB32());
    expect(middle.toARGB32(), isNot(trafficRamp[0].$2.toARGB32()));
  });

  test('the stretches hold their place to a fraction of a pixel in 32 bits, '
      'where the map plane itself would step them by pixels', () {
    // across Lviv, west to east and south to north
    const streets = Streets([
      [LatLng(49.80, 23.95), LatLng(49.81, 23.96)],
      [LatLng(49.87, 24.10), LatLng(49.88, 24.11)],
    ]);

    final plane = projectStreets(streets);

    final coords = [
      for (final line in plane.lines)
        for (final p in line) ...[p.dx, p.dy],
    ];
    expect(
      coords.every((v) => (_asF32(v) - v).abs() < _f32ToleratedPx),
      isTrue,
    );
    final raw = const Epsg3857().latLngToOffset(streets.lines.last.last, 18);
    expect((_asF32(raw.dx) - raw.dx).abs(), greaterThan(_f32ToleratedPx));
  });
}
