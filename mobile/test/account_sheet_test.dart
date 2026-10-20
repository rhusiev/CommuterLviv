import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:commuterlviv/src/sheets.dart';
import 'package:commuterlviv/src/strings.dart';

Widget _sheet({
  required double? hurry,
  VoidCallback? onSpeed,
  VoidCallback? onPassword,
  VoidCallback? onOut,
  bool canChangePassword = true,
}) => MaterialApp(
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
      onPassword: canChangePassword ? onPassword ?? () {} : null,
      onOut: onOut ?? () {},
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

  testWidgets('the password row opens the change', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      _sheet(hurry: null, onPassword: () => opened = true),
    );

    await tester.tap(find.text(txt.changePassword));

    expect(opened, isTrue);
  });

  testWidgets('no password row where the service does not allow a change', (
    tester,
  ) async {
    await tester.pumpWidget(_sheet(hurry: null, canChangePassword: false));

    expect(find.text(txt.changePassword), findsNothing);
  });

  testWidgets('sign out is reachable on a short screen', (tester) async {
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var out = false;
    await tester.pumpWidget(_sheet(hurry: null, onOut: () => out = true));

    await tester.ensureVisible(find.text(txt.signOut));
    await tester.tap(find.text(txt.signOut));

    expect(out, isTrue);
  });
}
