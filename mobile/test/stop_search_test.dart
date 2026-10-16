import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/stop_search.dart';
import 'package:commuterlviv/src/strings.dart';

const _catalog = Catalog(
  routes: [],
  stops: [
    Stop(
      id: 's0',
      name: 'Market',
      code: '100',
      lat: 49.84,
      lon: 24.03,
      routes: [],
    ),
  ],
  index: {},
  stopIndex: {},
);

const _home = Place(name: 'Market home', at: LatLng(49.85, 24.04));
const _work = Place(name: 'Work', at: LatLng(49.83, 24.02));

/// Past the debounce, so the service has been asked and has failed: tests get
/// no network
const _settled = Duration(seconds: 1);

/// Opens the search over [places]; the hit it closes with lands in [picked]
Future<void> open(WidgetTester tester, void Function(Hit?) picked) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final api = await Api.open();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => picked(
            await showSearch<Hit?>(
              context: context,
              delegate: StopSearch(
                api: api,
                catalog: _catalog,
                places: const [_work, _home],
                onSave: (_, _) {},
              ),
            ),
          ),
          child: const Text('search'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('search'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a saved place the query matches comes first, and is picked as '
      'a place', (tester) async {
    Hit? picked;
    await open(tester, (hit) => picked = hit);

    await tester.enterText(find.byType(TextField), 'mark');
    await tester.pump(_settled);

    expect(find.text(_work.name), findsNothing);
    final order = [txt.places, _home.name, txt.foundStops, 'Market'];
    final tops = [for (final t in order) tester.getTopLeft(find.text(t)).dy];
    expect(tops, orderedEquals([...tops]..sort()));
    await tester.tap(find.text(_home.name));
    await tester.pumpAndSettle();
    expect(picked, isA<PlaceHit>().having((p) => p.at, 'at', _home.at));
  });
}
