import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/sheets.dart';

/// A chip's tooltip is shown on a long press and wins the gesture arena, so a
/// tooltip here would stop the line ever opening.
void main() {
  testWidgets('the route sheet opens a line on a long press', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final api = await Api.open();
    final catalog = Catalog(
      routes: [
        TransitRoute(id: 'r48', short: '48', long: 'A to B', type: 'bus'),
      ],
      stops: const [],
      index: const {'r48': 0},
      stopIndex: const {},
    );
    var opened = -1;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RouteSheet(
          api: api,
          catalog: catalog,
          sets: null,
          picked: <int>{},
          onToggle: (_) {},
          onClear: () {},
          onActivated: (_, _) {},
          onSets: (_) {},
          onRoute: (i) => opened = i,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('48'));
    await tester.pumpAndSettle();
    expect(opened, 0);
  });
}
