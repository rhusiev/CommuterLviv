import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:commuterlviv/src/sheets.dart';
import 'package:commuterlviv/src/strings.dart';

Widget _sheet({required double? hurry, VoidCallback? onSpeed}) => MaterialApp(
  home: Scaffold(
    body: AccountSheet(
      server: 'https://example.org',
      speed: 4.5,
      hurry: hurry,
      followAway: false,
      onFollowAway: (_) {},
      onSaved: () {},
      onLanguage: () {},
      onSpeed: onSpeed ?? () {},
      onServer: () {},
      onOut: () {},
    ),
  ),
);

void main() {
  testWidgets('the speeds row names both speeds and opens their sheet', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(_sheet(hurry: 6, onSpeed: () => opened = true));

    expect(find.text(txt.paces), findsOneWidget);
    expect(find.text(txt.pacesNow(4.5, 6)), findsOneWidget);
    expect(txt.pacesNow(4.5, 6), contains(txt.kmh(6)));
    await tester.tap(find.text(txt.paces));
    expect(opened, isTrue);
  });

  testWidgets('the speeds row says when hurrying is off', (tester) async {
    await tester.pumpWidget(_sheet(hurry: null));

    expect(find.text(txt.pacesNow(4.5, null)), findsOneWidget);
    expect(txt.pacesNow(4.5, null), isNot(txt.pacesNow(4.5, 4.5)));
  });
}
