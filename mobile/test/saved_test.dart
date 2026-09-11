import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/saved.dart';
import 'package:commuterlviv/src/strings.dart';

final _catalog = Catalog(
  routes: const [
    TransitRoute(id: 'r48', short: '48', long: 'A to B', type: 'bus'),
  ],
  stops: const [
    Stop(
      id: 's1',
      name: 'Opera',
      code: '1',
      lat: 49.84,
      lon: 24.03,
      routes: [0],
    ),
  ],
  index: const {'r48': 0},
  stopIndex: const {'s1': 0},
);

/// The sheet pops itself when a row is tapped, so it is pushed over a page of
/// its own rather than being the only route there is.
Future<void> pump(WidgetTester tester, Widget sheet) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(builder: (_) => Scaffold(body: sheet)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a rename rewrites the whole list, in order', (tester) async {
    List<Place>? written;
    await pump(
      tester,
      SavedSheet(
        catalog: _catalog,
        places: const [
          Place(name: 'Home', at: LatLng(49.8, 24.0)),
          Place(name: 'Work', at: LatLng(49.9, 24.1)),
        ],
        pins: const [],
        onPlaces: (places) => written = places,
        onPins: (_) {},
        onShowPlace: (_) {},
        onShowStop: (_) {},
      ),
    );

    await tester.longPress(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(txt.rename));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Flat');
    await tester.tap(find.text(txt.save));
    await tester.pumpAndSettle();

    expect([for (final p in written!) p.name], ['Flat', 'Work']);
    expect(written!.first.at, const LatLng(49.8, 24.0));
  });

  testWidgets('a pinned stop can be dropped but not renamed', (tester) async {
    List<int>? written;
    await pump(
      tester,
      SavedSheet(
        catalog: _catalog,
        places: const [],
        pins: const [0],
        onPlaces: (_) {},
        onPins: (pins) => written = pins,
        onShowPlace: (_) {},
        onShowStop: (_) {},
      ),
    );

    await tester.longPress(find.text('Opera'));
    await tester.pumpAndSettle();
    expect(find.text(txt.rename), findsNothing);
    await tester.tap(find.text(txt.delete));
    await tester.pumpAndSettle();

    expect(written, isEmpty);
    expect(find.text(txt.nothingSaved), findsOneWidget);
  });

  testWidgets('a tap shows the place on the map', (tester) async {
    LatLng? shown;
    await pump(
      tester,
      SavedSheet(
        catalog: _catalog,
        places: const [Place(name: 'Home', at: LatLng(49.8, 24.0))],
        pins: const [],
        onPlaces: (_) {},
        onPins: (_) {},
        onShowPlace: (at) => shown = at,
        onShowStop: (_) {},
      ),
    );

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(shown, const LatLng(49.8, 24.0));
  });
}
