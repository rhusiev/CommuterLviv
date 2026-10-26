import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/main.dart';
import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/sign_in.dart';
import 'package:commuterlviv/src/strings.dart';

/// Material's index of Monday, the first day of its week from Sunday
const _monday = 1;

void main() {
  testWidgets("Flutter's own words and the week follow the app's language, "
      'also when it changes', (tester) async {
    useLang(Lang.uk);
    addTearDown(() => useLang(Lang.uk));
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final api = await Api.open();

    // The test binding refuses every request, so no session resumes and the
    // app stays on the sign-in screen
    await tester.pumpWidget(CommuterLvivApp(api: api));
    await tester.pumpAndSettle();
    MaterialLocalizations words() =>
        MaterialLocalizations.of(tester.element(find.byType(SignInScreen)));

    expect(words().backButtonTooltip, 'Назад');
    expect(words().datePickerHelpText, 'Вибрати дату');
    expect(words().firstDayOfWeekIndex, _monday);

    useLang(Lang.en);
    await tester.pumpAndSettle();

    expect(words().backButtonTooltip, 'Back');
    expect(words().datePickerHelpText, 'Select date');
  });
}
