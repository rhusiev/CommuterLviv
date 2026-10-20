import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/live.dart';
import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/stop_card.dart';

const _catalog = Catalog(
  routes: [
    TransitRoute(id: 'r1', short: '1', long: 'A to B', type: 'bus'),
    TransitRoute(id: 'r9', short: '9', long: 'C to D', type: 'bus'),
  ],
  stops: [
    Stop(
      id: 's1',
      name: 'Square',
      code: '',
      lat: 49.84,
      lon: 24.03,
      routes: [0, 1],
    ),
  ],
  index: {'r1': 0, 'r9': 1},
  stopIndex: {'s1': 0},
);

Finder _chip(String short) =>
    find.ancestor(of: find.text(short), matching: find.byType(FilterChip));

bool _picked(WidgetTester tester, String short) =>
    tester.widget<FilterChip>(_chip(short)).selected;

void main() {
  testWidgets('a watched route that calls here is picked, the rest are not', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final api = await Api.open();
    int? toggled;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StopCard(
            catalog: _catalog,
            live: Live(api, onRenewed: () {}),
            stop: 0,
            pinned: false,
            watching: const {0},
            onPin: () {},
            onRoute: (r) => toggled = r,
            onLine: (_) {},
          ),
        ),
      ),
    );

    expect(_picked(tester, '1'), isTrue);
    expect(_picked(tester, '9'), isFalse);
    expect(find.byIcon(Icons.check), findsNothing);
    await tester.tap(_chip('9'));
    expect(toggled, 1);
  });
}
