import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/live.dart';
import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/route_chip.dart';
import 'package:commuterlviv/src/stop_card.dart';

const _catalog = Catalog(
  routes: [
    TransitRoute(id: 'r1', short: '1', long: 'A to B', type: 'bus'),
    TransitRoute(id: 'r9', short: '9', long: 'C to D', type: 'bus'),
  ],
  stops: [
    Stop(
      id: 's1',
      name: 'Square (482)',
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
    find.ancestor(of: find.text(short), matching: find.byType(RouteChip));

bool _picked(WidgetTester tester, String short) =>
    tester.widget<RouteChip>(_chip(short)).watched;

void main() {
  testWidgets('the card names the stop once and picks the watched routes', (
    tester,
  ) async {
    final watching = {0};
    final (:lines) = await _pump(
      tester,
      watching: watching,
      onRoute: (r) =>
          watching.contains(r) ? watching.remove(r) : watching.add(r),
    );

    expect(find.text('Square (482)', findRichText: true), findsOneWidget);
    expect(find.textContaining('482'), findsOneWidget);
    expect(_picked(tester, '1'), isTrue);
    expect(_picked(tester, '9'), isFalse);
    expect(find.byIcon(Icons.check), findsNothing);
    await tester.tap(find.text('9'));
    await tester.pump();
    expect(watching, {0, 1});
    // the card stays open and shows the route watched
    expect(_picked(tester, '9'), isTrue);
    expect(lines, isEmpty);
  });

  testWidgets('a chip opens its line from its chevron, not from a long press', (
    tester,
  ) async {
    final (:lines) = await _pump(tester, watching: {}, onRoute: (_) {});

    await tester.longPress(find.text('9'));
    expect(lines, isEmpty);
    await tester.tap(
      find.descendant(
        of: _chip('9'),
        matching: find.byIcon(Icons.chevron_right),
      ),
    );
    expect(lines, [1]);
  });
}

Future<({List<int> lines})> _pump(
  WidgetTester tester, {
  required Set<int> watching,
  required void Function(int route) onRoute,
}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final api = await Api.open();
  final lines = <int>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StopCard(
          catalog: _catalog,
          live: Live(api, onRenewed: () {}),
          stop: 0,
          pinned: false,
          watching: watching,
          onPin: () {},
          onRoute: onRoute,
          onLine: lines.add,
        ),
      ),
    ),
  );
  return (lines: lines);
}
