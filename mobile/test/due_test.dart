import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:commuterlviv/src/due.dart';
import 'package:commuterlviv/src/eta.dart';
import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/strings.dart';

const _catalog = Catalog(
  routes: [TransitRoute(id: 'r48', short: 'А48', long: 'A to B', type: 'bus')],
  stops: [],
  index: {'r48': 0},
  stopIndex: {},
);

/// Seconds ahead an arrival is due, so its countdown reads in minutes
const _dueS = 300;

Future<Arrival> _pump(
  WidgetTester tester, {
  Doubt? doubt,
  bool lowFloor = false,
  bool marked = false,
}) async {
  final a = Arrival(
    route: 0,
    veh: 7,
    t: DateTime.now().millisecondsSinceEpoch ~/ 1000 + _dueS,
    doubt: doubt,
    lowFloor: lowFloor,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Due(
              route: _catalog.routes[0],
              arrival: a,
              watched: false,
              onWatch: () {},
              onLine: () {},
              lowFloor: marked,
            ),
            Doubts(catalog: _catalog, due: [a]),
          ],
        ),
      ),
    ),
  );
  return a;
}

void main() {
  testWidgets('a doubted time is amber and says why, by the badge number', (
    tester,
  ) async {
    final a = await _pump(tester, doubt: Doubt.stuck);

    final time = tester.widget<Text>(find.text(countdown(a.t)));
    expect(time.style?.color, doubtColour);
    expect(find.text(txt.doubtStuck('48')), findsOneWidget);
  });

  testWidgets('a sure time says nothing more', (tester) async {
    await _pump(tester);

    expect(find.text(txt.doubtStuck('48')), findsNothing);
    expect(find.text(txt.doubtSilent('48')), findsNothing);
  });

  testWidgets('a low-floor vehicle is marked only when asked to', (
    tester,
  ) async {
    await _pump(tester, lowFloor: true, marked: true);
    expect(find.byIcon(Icons.accessible), findsOneWidget);

    await _pump(tester, lowFloor: true);
    expect(find.byIcon(Icons.accessible), findsNothing);
  });
}
