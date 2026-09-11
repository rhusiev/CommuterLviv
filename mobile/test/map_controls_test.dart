import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:commuterlviv/src/here.dart';
import 'package:commuterlviv/src/map_controls.dart';
import 'package:commuterlviv/src/strings.dart';

/// No tile layer: the controls only read the camera.
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
          MapControls(map: map, here: Here(onFirstFix: (_) {})),
        ],
      ),
    ),
  );
  return map;
}

void main() {
  testWidgets('the buttons zoom, and stop at the ends', (tester) async {
    final map = await pump(tester);

    await tester.tap(find.byTooltip(txt.zoomIn));
    await tester.pump();
    expect(map.camera.zoom, 14);

    await tester.tap(find.byTooltip(txt.zoomOut));
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
    expect(find.byTooltip(txt.faceNorth), findsNothing);

    map.rotate(30);
    await tester.pump();
    expect(find.byTooltip(txt.faceNorth), findsOneWidget);
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

    await tester.tap(find.byTooltip(txt.faceNorth));
    await tester.pump();
    expect(map.camera.rotation, 0);
    expect(find.byTooltip(txt.faceNorth), findsNothing);
  });
}
