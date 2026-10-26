import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:commuterlviv/src/place_card.dart';
import 'package:commuterlviv/src/strings.dart';

const _where = 'Lviv, Halytskyi district';

Future<void> _pump(
  WidgetTester tester, {
  bool saved = false,
  VoidCallback? onSave,
  VoidCallback? onGo,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: PlaceCard(
        name: 'Rynok',
        where: _where,
        saved: saved,
        onSave: onSave ?? () {},
        onGo: onGo ?? () {},
      ),
    ),
  ),
);

void main() {
  testWidgets('a found place reads over its address and is saved by its star', (
    tester,
  ) async {
    var saves = 0;
    await _pump(tester, onSave: () => saves++);
    expect(find.text('Rynok'), findsOneWidget);
    expect(find.text(_where), findsOneWidget);

    await tester.tap(find.byTooltip(txt.savePlace));
    await tester.pump();

    expect(saves, 1);
    expect(find.text(txt.saved), findsOneWidget);
    expect(find.byTooltip(txt.savePlace), findsNothing);
  });

  testWidgets('a saved place says so, with nothing to save again', (
    tester,
  ) async {
    await _pump(tester, saved: true);

    expect(find.text(txt.saved), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.byTooltip(txt.savePlace), findsNothing);
  });

  testWidgets('the card plans the way there', (tester) async {
    var went = false;
    await _pump(tester, onGo: () => went = true);

    await tester.tap(find.text(txt.getHere));

    expect(went, isTrue);
  });
}
