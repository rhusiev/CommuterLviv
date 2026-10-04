import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/here.dart';
import 'package:commuterlviv/src/live.dart';
import 'package:commuterlviv/src/map_tab.dart';
import 'package:commuterlviv/src/map_theme.dart';
import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/strings.dart';

const _card = Key('card');

Future<void> pump(WidgetTester tester, {Widget? card}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final api = await Api.open();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MapTab(
          api: api,
          map: MapController(),
          style: null,
          traffic: false,
          catalog: const Catalog(
            routes: [],
            stops: [],
            index: {},
            stopIndex: {},
          ),
          live: Live(api, onRenewed: () {}),
          stops: const [],
          selected: null,
          theme: mapThemes.first,
          here: Here(onFirstFix: (_) {}),
          card: card,
          empty: false,
          marks: const [],
          journey: null,
          pins: const [],
          places: const [],
          shapes: null,
          lines: const [],
          arrowed: null,
          onTap: (_) {},
          onHold: (_) {},
        ),
      ),
    ),
  );
}

Widget _cardOf({required bool isOffstage}) => Offstage(
  offstage: isOffstage,
  child: const SizedBox(key: _card, height: 80),
);

Rect _zoomOut(WidgetTester tester) =>
    tester.getRect(find.byTooltip(txt.zoomOut));

void main() {
  testWidgets('a card goes under the map buttons, across the width', (
    tester,
  ) async {
    await pump(tester, card: _cardOf(isOffstage: false));
    final card = tester.getRect(find.byKey(_card));
    expect(card.top, greaterThanOrEqualTo(_zoomOut(tester).bottom));
    final width = tester.getSize(find.byType(MapTab)).width;
    expect(card.width, greaterThan(width / 2));
  });

  testWidgets('an offstage card leaves the buttons where they were', (
    tester,
  ) async {
    await pump(tester);
    final alone = _zoomOut(tester);
    await pump(tester, card: _cardOf(isOffstage: true));
    expect(_zoomOut(tester), alone);
  });
}
