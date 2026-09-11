import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/journey_panel.dart';
import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/strings.dart';

Future<void> pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final api = await Api.open();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: JourneyPanel(
          api: api,
          catalog: const Catalog(
            routes: [],
            stops: [],
            index: {},
            stopIndex: {},
          ),
          from: null,
          to: null,
          picking: null,
          onPick: (_) {},
          onSwap: () {},
          onHere: (_) {},
          onStop: (_) {},
          onLine: (_) {},
          places: const [],
          onSave: (_, _) {},
          onForget: (_) {},
          onPlace: (_, _) {},
          onClose: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the depart chip leaves at now until a time is picked', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text(txt.departAt), findsOneWidget);
    expect(find.text(txt.now), findsOneWidget);

    await tester.tap(find.text(txt.now));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
  });

  test('each ride says what it rests on', () {
    expect(legPart(Confidence.live), txt.livePart);
    expect(legPart(Confidence.schedule), txt.schedulePart);
    expect(legPart(Confidence.quiet), txt.quietPart);
  });
}
