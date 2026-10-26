import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/sign_in.dart';
import 'package:commuterlviv/src/strings.dart';

import 'back.dart';

void main() {
  testWidgets('back from taking up an invite returns to signing in', (
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
    await tester.tap(find.text(txt.haveInvite));
    await tester.pump();
    expect(find.text(txt.inviteCode), findsOneWidget);

    expect(await pressBack(tester), isFalse);
    expect(find.text(txt.inviteCode), findsNothing);
    expect(find.text(txt.signIn), findsOneWidget);
    expect(await pressBack(tester), isTrue);
  });
}
