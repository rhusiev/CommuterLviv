import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/live.dart';
import 'package:commuterlviv/src/quiet_banner.dart';
import 'package:commuterlviv/src/strings.dart';

/// A [Live] that is told rather than connected.
class _Live extends Live {
  _Live(super.api) : super(onRenewed: () {});

  void say(bool now) {
    quiet = now;
    notifyListeners();
  }
}

Future<_Live> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final live = _Live(await Api.open());
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: QuietBanner(live: live)),
    ),
  );
  return live;
}

void main() {
  testWidgets('the banner shows only while the vehicles are quiet', (
    tester,
  ) async {
    final live = await _pump(tester);
    expect(find.text(txt.quiet), findsNothing);

    live.say(true);
    await tester.pump();
    expect(find.text(txt.quiet), findsOneWidget);

    live.say(false);
    await tester.pump();
    expect(find.text(txt.quiet), findsNothing);
  });

  testWidgets(
    'a closed banner stays closed until the vehicles go quiet again',
    (tester) async {
      final live = await _pump(tester)
        ..say(true);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.text(txt.quiet), findsNothing);
      live.say(true);
      await tester.pump();
      expect(find.text(txt.quiet), findsNothing);

      live.say(false);
      await tester.pump();
      live.say(true);
      await tester.pump();
      expect(find.text(txt.quiet), findsOneWidget);
    },
  );
}
