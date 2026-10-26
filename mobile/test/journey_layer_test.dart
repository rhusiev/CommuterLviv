import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:commuterlviv/src/eta.dart';
import 'package:commuterlviv/src/journey_layer.dart';
import 'package:commuterlviv/src/map_theme.dart';
import 'package:commuterlviv/src/models.dart';

const _t0 = 1790000040;
const _walkS = 600;
const _door = LatLng(49.84, 24.0);
const _home = LatLng(49.85, 24.0);

/// Half a place's name plate, which is drawn level with its dot
const _plateHalf = 8.0;

/// A walk from a door to a saved place, drawn on a map centred between them
Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(49.845, 24.0),
          initialZoom: 15,
        ),
        children: [
          JourneyLayer(
            journey: const Journey(
              dep: _t0,
              arr: _t0 + _walkS,
              rides: 0,
              live: false,
              confidence: Confidence.schedule,
              legs: [
                Leg(
                  kind: 'walk',
                  dep: _t0,
                  arr: _t0 + _walkS,
                  a: -1,
                  b: -1,
                  pts: [_door, _home],
                ),
              ],
            ),
            catalog: const Catalog(
              routes: [],
              stops: [],
              index: {},
              stopIndex: {},
            ),
            theme: const MapTheme('x', dark: true),
            places: const [Place(name: 'Home', at: _home)],
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('a pill on a saved place stands above it, clear of its name', (
    tester,
  ) async {
    await _pump(tester);
    final camera = MapCamera.of(tester.element(find.byType(JourneyLayer)));

    final home = camera.latLngToScreenOffset(_home);
    final atHome = tester.getRect(find.text(clockTime(_t0 + _walkS)));
    expect(atHome.bottom, lessThan(home.dy - _plateHalf));
    expect(atHome.center.dx, moreOrLessEquals(home.dx));

    final door = camera.latLngToScreenOffset(_door);
    final atDoor = tester.getRect(find.text(clockTime(_t0)));
    expect(atDoor.center.dy, moreOrLessEquals(door.dy));
  });
}
