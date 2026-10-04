import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:commuterlviv/src/here.dart';
import 'package:commuterlviv/src/map_controls.dart';
import 'package:commuterlviv/src/strings.dart';
import 'package:commuterlviv/src/tracking.dart';

const start = LatLng(49.8397, 24.0297);
const zoom = 15.0;

/// A map with the controls over it, a `Here` fed by [fix], and the tracking
/// under test, which the locate button resumes as the home screen has it.
Future<
  ({MapController map, Tracking tracking, Future<void> Function(LatLng) fix})
>
pump(WidgetTester tester) async {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('nl.r1a.commuterlviv/here'),
    (_) async => true,
  );
  MockStreamHandlerEventSink? sink;
  messenger.setMockStreamHandler(
    const EventChannel('nl.r1a.commuterlviv/here/fixes'),
    MockStreamHandler.inline(
      onListen: (_, events) {
        sink = events;
      },
    ),
  );
  final map = MapController();
  final here = Here(onFirstFix: (_) {});
  final tracking = Tracking(map, here);
  addTearDown(tracking.stop);
  await tester.pumpWidget(
    MaterialApp(
      home: Stack(
        children: [
          FlutterMap(
            mapController: map,
            options: const MapOptions(initialCenter: start, initialZoom: zoom),
            children: const [],
          ),
          MapControls(map: map, here: here, onLocate: tracking.start),
        ],
      ),
    ),
  );
  await here.start();
  Future<void> fix(LatLng at) async {
    sink!.success({
      'lat': at.latitude,
      'lon': at.longitude,
      'accuracy': 10.0,
      't': 0.0,
    });
    await tester.pump();
  }

  return (map: map, tracking: tracking, fix: fix);
}

void main() {
  testWidgets('while held, each fix centres the camera at the same zoom', (
    tester,
  ) async {
    final t = await pump(tester);
    t.tracking.start();

    await t.fix(const LatLng(49.84, 24.02));
    await t.fix(const LatLng(49.845, 24.025));

    expect(t.map.camera.center, const LatLng(49.845, 24.025));
    expect(t.map.camera.zoom, zoom);
  });

  testWidgets(
    'a drag lets go of the dot, and the locate button takes it back',
    (tester) async {
      final t = await pump(tester);
      t.tracking.start();
      await t.fix(const LatLng(49.84, 24.02));

      await tester.drag(find.byType(FlutterMap), const Offset(200, 0));
      await tester.pumpAndSettle();
      final looked = t.map.camera.center;
      await t.fix(const LatLng(49.845, 24.025));

      expect(t.tracking.held, isFalse);
      expect(t.map.camera.center, looked);

      await tester.tap(find.byTooltip(txt.whereAmI));
      await tester.pump();
      await t.fix(const LatLng(49.85, 24.03));

      expect(t.tracking.held, isTrue);
      expect(t.map.camera.center, const LatLng(49.85, 24.03));
    },
  );

  testWidgets('a zoom button keeps hold of the dot', (tester) async {
    final t = await pump(tester);
    t.tracking.start();

    await tester.tap(find.byTooltip(txt.zoomIn));
    await tester.pump();
    await t.fix(const LatLng(49.84, 24.02));

    expect(t.map.camera.center, const LatLng(49.84, 24.02));
    expect(t.map.camera.zoom, zoom + 1);
  });

  testWidgets('once stopped, fixes leave the camera alone', (tester) async {
    final t = await pump(tester);
    t.tracking.start();
    t.tracking.stop();

    await t.fix(const LatLng(49.84, 24.02));

    expect(t.map.camera.center, start);
  });
}
