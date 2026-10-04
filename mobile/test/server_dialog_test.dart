import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/sign_in.dart';
import 'package:commuterlviv/src/strings.dart';

const local = 'http://10.0.2.2:8080';

void main() {
  testWidgets('a server changed on the sign-in screen is the one used', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final api = await Api.open();
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(api: api, onIn: (_) {}),
      ),
    );

    await tester.tap(find.text(api.base));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, local);
    await tester.tap(find.text(txt.use));
    await tester.pumpAndSettle();

    expect(api.base, local);
    expect(find.text(local), findsOneWidget);
  });
}
