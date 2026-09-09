import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:commuterlviv/src/map_controls.dart';

/// A map with the buttons over it, and no tile layer: the controls only ever
/// read the camera, and a test has no network.
Future<MapController> pump(WidgetTester tester, {double zoom = 13}) async {
  final map = MapController();
  await tester.pumpWidget(
    MaterialApp(
      home: Stack(
        children: [
          FlutterMap(
            mapController: map,
            options: MapOptions(
              initialCenter: const LatLng(49.8397, 24.0297),
              initialZoom: zoom,
              minZoom: minZoom,
              maxZoom: maxZoom,
            ),
            children: const [],
          ),
          MapControls(map: map),
        ],
      ),
    ),
  );
  return map;
}

void main() {
  testWidgets('the buttons zoom, and stop at the ends', (tester) async {
    final map = await pump(tester);

    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(map.camera.zoom, 14);

    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pump();
    expect(map.camera.zoom, 13);

    map.move(map.camera.center, maxZoom);
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
          .onPressed,
      isNull,
    );

    map.move(map.camera.center, minZoom);
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove))
          .onPressed,
      isNull,
    );
  });

  testWidgets('the compass shows up only off north, and puts the map back', (
    tester,
  ) async {
    final map = await pump(tester);
    expect(find.byTooltip('Face north'), findsNothing);

    map.rotate(30);
    await tester.pump();
    expect(find.byTooltip('Face north'), findsOneWidget);
    expect(
      tester
          .widget<Transform>(
            find
                .ancestor(
                  of: find.byIcon(Icons.navigation_outlined),
                  matching: find.byType(Transform),
                )
                .first,
          )
          .transform
          .getRotation()
          .getColumn(0)
          .x,
      closeTo(0.866, 0.001), // cos 30°: the needle turns with the map
    );

    await tester.tap(find.byTooltip('Face north'));
    await tester.pump();
    expect(map.camera.rotation, 0);
    expect(find.byTooltip('Face north'), findsNothing);
  });
}
