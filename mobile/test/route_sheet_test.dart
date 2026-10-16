import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/sheets.dart';

/// A chip's tooltip is shown on a long press and wins the gesture arena, so a
/// tooltip here would stop the line ever opening.
const _catalog = Catalog(
  routes: [TransitRoute(id: 'r48', short: '48', long: 'A to B', type: 'bus')],
  stops: [],
  index: {'r48': 0},
  stopIndex: {},
);

/// The sheet over [_catalog] with [sets], opening a line with [onRoute].
Future<void> _pump(
  WidgetTester tester, {
  Sets? sets,
  void Function(int route)? onRoute,
}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final api = (await tester.runAsync(Api.open))!;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RouteSheet(
          api: api,
          catalog: _catalog,
          sets: sets,
          picked: <int>{},
          onToggle: (_) {},
          onClear: () {},
          onActivated: (_, _) {},
          onSets: (_) {},
          onRoute: onRoute ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the route sheet opens a line on a long press', (tester) async {
    var opened = -1;
    await _pump(tester, onRoute: (i) => opened = i);
    await tester.longPress(find.widgetWithText(FilterChip, '48'));
    await tester.pumpAndSettle();
    expect(opened, 0);
  });

  testWidgets('a set the server refuses to show says why', (tester) async {
    // The test binding answers every request 400
    await _pump(
      tester,
      sets: const Sets(
        sets: [
          RouteSet(id: 'set-1', name: 'home', routes: ['r48'], ord: 0),
        ],
        active: null,
        pins: [],
        places: [],
      ),
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'home'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('The server said 400'), findsOneWidget);
  });
}
