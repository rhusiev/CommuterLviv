import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:commuterlviv/src/map_controls.dart';

const _center = Offset(400, 300);

/// Half the distance between the fingers. Must be a hand's width: a twist moves
/// each finger along a chord of this radius, and below Flutter's scale slop the
/// gesture is never recognised at all.
const _reach = 120.0;

Future<MapController> pump(WidgetTester tester) async {
  final map = MapController();
  await tester.pumpWidget(
    MaterialApp(
      home: FlutterMap(
        mapController: map,
        options: MapOptions(
          initialCenter: const LatLng(49.8397, 24.0297),
          initialZoom: 13,
          minZoom: minZoom,
          maxZoom: maxZoom,
          interactionOptions: mapInteraction,
        ),
        children: const [],
      ),
    ),
  );
  return map;
}

Offset _finger(double degrees, double reach) {
  final a = degrees * math.pi / 180;
  return _center + Offset(math.cos(a), math.sin(a)) * reach;
}

/// Two fingers opposite each other, turned by [turn] degrees and pulled apart
/// by [spread], in the small steps a real touch arrives in.
Future<void> pinch(
  WidgetTester tester, {
  double turn = 0,
  double spread = 1,
}) async {
  final one = await tester.startGesture(_finger(0, _reach), pointer: 1);
  final two = await tester.startGesture(_finger(180, _reach), pointer: 2);
  for (var i = 1; i <= 10; i++) {
    final at = _reach * (1 + (spread - 1) * i / 10);
    await one.moveTo(_finger(turn * i / 10, at));
    await two.moveTo(_finger(180 + turn * i / 10, at));
    await tester.pump();
  }
  await one.up();
  await two.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the twist a pinch carries does not turn the map', (
    tester,
  ) async {
    final map = await pump(tester);
    await pinch(tester, turn: 8, spread: 2);

    expect(map.camera.rotation, 0);
    expect(map.camera.zoom, greaterThan(13));
  });

  testWidgets('a twist meant as one does turn it', (tester) async {
    final map = await pump(tester);
    await pinch(tester, turn: 20);

    expect(map.camera.rotation, greaterThan(0));
  });
}
