import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:commuterlviv/src/hold_sheet.dart';
import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/strings.dart';

const _at = LatLng(49.84187, 24.03142);

/// A city whose one stop, [_opera], is 111 m north of [_at]
const _city = Catalog(routes: [], stops: [_opera], index: {}, stopIndex: {});

const _opera = Stop(
  id: 's0',
  name: 'Opera (7)',
  code: '7',
  lat: 49.84287,
  lon: 24.03142,
  routes: [],
);

const _nowhere = Catalog(routes: [], stops: [], index: {}, stopIndex: {});

/// What the sheet was asked to do, in order
final _done = <String>[];

Future<void> _pump(WidgetTester tester, {Catalog catalog = _nowhere}) {
  _done.clear();
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HoldSheet(
          at: _at,
          catalog: catalog,
          onSave: (name) => _done.add('save $name'),
          onTo: () => _done.add('to'),
          onFrom: () => _done.add('from'),
          onNear: () => _done.add('near'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a held point says where it is and offers the four actions', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('49.8419, 24.0314'), findsOneWidget);
    for (final (label, done) in [
      (txt.toHere, 'to'),
      (txt.fromHere, 'from'),
      (txt.nearHere, 'near'),
    ]) {
      await tester.tap(find.text(label));
      expect(_done.last, done);
    }
    expect(find.text(txt.savePlaceAs), findsOneWidget);
  });

  testWidgets('a held point near a stop is called by it', (tester) async {
    await _pump(tester, catalog: _city);

    expect(find.text(txt.nearStop('Opera')), findsOneWidget);
  });

  testWidgets('a held point is named in the sheet itself, not a dialog', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text(txt.savePlaceAs));
    await tester.pump();

    expect(find.byType(Dialog), findsNothing);
    final save = find.widgetWithText(FilledButton, txt.saveHere);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '  Corner ');
    await tester.pump();
    await tester.tap(save);

    expect(_done, ['save Corner']);
  });
}
