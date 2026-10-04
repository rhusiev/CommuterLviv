import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

import 'package:commuterlviv/src/sheets.dart';
import 'package:commuterlviv/src/strings.dart';

void main() {
  LeakTesting.enable();
  testWidgets(
    'the name dialog answers the trimmed field and leaks no controller',
    experimentalLeakTesting: LeakTesting.settings.withTrackedAll(),
    (tester) async {
      String? got;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => got = await askName(context, 'Name'),
              child: const Text('ask'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  Home ');
      await tester.tap(find.text(txt.save));
      await tester.pumpAndSettle();

      expect(got, 'Home');
    },
  );
}
