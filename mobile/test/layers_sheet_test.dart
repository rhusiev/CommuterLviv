import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:commuterlviv/src/map_theme.dart';
import 'package:commuterlviv/src/sheets.dart';
import 'package:commuterlviv/src/strings.dart';

Future<void> _pump(WidgetTester tester, Lang lang) async {
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
}
