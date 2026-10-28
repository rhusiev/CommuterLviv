import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:commuterlviv/src/map_theme.dart';
import 'package:commuterlviv/src/sheets.dart';
import 'package:commuterlviv/src/strings.dart';
import 'package:commuterlviv/src/theme.dart';

Future<void> _pump(
  WidgetTester tester,
  Lang lang, {
  ValueChanged<bool>? onBlur,
}) async {
  useLang(lang);
  addTearDown(() => useLang(Lang.uk));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LayersSheet(
          lines: false,
          onLines: (_) {},
          traffic: false,
          onTraffic: (_) {},
          theme: mapThemes.first,
          onTheme: (_) {},
          blur: true,
          onBlur: onBlur ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('names the basemaps in Ukrainian', (tester) async {
    await _pump(tester, Lang.uk);
    expect(find.text('Кольорова темна'), findsOneWidget);
    expect(find.text('Сіра'), findsOneWidget);
    expect(find.textContaining('Gray'), findsNothing);
  });

  testWidgets('names the basemaps in English', (tester) async {
    await _pump(tester, Lang.en);
    expect(find.text('Colorful dark'), findsOneWidget);
    expect(find.text('Gray'), findsOneWidget);
  });

  test('every basemap has a name in both languages', () {
    for (final l in Lang.values) {
      useLang(l);
      for (final t in mapThemes) {
        expect(txt.themeNames[t.id], isNotNull, reason: '${t.id} in $l');
      }
    }
    useLang(Lang.uk);
  });

  testWidgets('the blur is a switch, on until turned off', (tester) async {
    final told = <bool>[];
    await _pump(tester, Lang.en, onBlur: told.add);

    await tester.tap(find.text(txt.blur));
    await tester.pump();

    expect(told, [false]);
  });

  testWidgets('a floating surface blurs the map unless the blur is off', (
    tester,
  ) async {
    Future<void> floating(bool on) => tester.pumpWidget(
      MaterialApp(
        home: Blurring(
          on: on,
          child: const Floating(child: SizedBox.square(dimension: 40)),
        ),
      ),
    );

    await floating(true);
    expect(find.byType(BackdropFilter), findsOneWidget);
    await floating(false);
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
