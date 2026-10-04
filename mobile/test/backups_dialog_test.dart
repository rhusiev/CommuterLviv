import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:commuterlviv/src/backups_dialog.dart';
import 'package:commuterlviv/src/eta.dart';
import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/strings.dart';

const _catalog = Catalog(
  routes: [
    TransitRoute(id: 'r38', short: '38', long: 'A to B', type: 'tram'),
    TransitRoute(id: 'r10', short: 'А10', long: 'C to D', type: 'bus'),
  ],
  stops: [
    Stop(id: 's0', name: 'Home stop', code: '0', lat: 0, lon: 0, routes: []),
    Stop(id: 's1', name: 'Work stop', code: '1', lat: 0, lon: 0, routes: []),
  ],
  index: {'r38': 0, 'r10': 1},
  stopIndex: {},
);

Leg _ride(int route, int dep, {List<Backup> backups = const []}) => Leg(
  kind: 'ride',
  dep: dep,
  arr: dep + 600,
  a: 0,
  b: 1,
  route: route,
  backups: backups,
);

final _journey = Journey(
  dep: 0,
  arr: 1000,
  rides: 1,
  live: true,
  confidence: Confidence.live,
  backup: 2,
  legs: [
    const Leg(kind: 'walk', dep: 0, arr: 100, a: -1, b: 0),
    _ride(
      0,
      100,
      backups: [
        Backup(rides: [_ride(1, 400)], arr: 1100),
        Backup(rides: [_ride(0, 700)], arr: 1400),
      ],
    ),
    const Leg(kind: 'walk', dep: 700, arr: 1000, a: 1, b: -1),
  ],
);

/// Opens the dialog from a button, answering each pick with [failure].
Future<List<WayPick?>> _open(WidgetTester tester, {String? failure}) async {
  final picked = <WayPick?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showBackups(
            context,
            journey: _journey,
            prefer: Prefer.changes,
            catalog: _catalog,
            place: (option) => option + 1,
            onWay: (pick) async {
              picked.add(pick);
              return failure;
            },
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return picked;
}

void main() {
  testWidgets('a backup is picked by its leg and its place among them', (
    tester,
  ) async {
    final picked = await _open(tester);

    await tester.tap(find.text(clockTime(1100)));
    await tester.pumpAndSettle();

    expect(picked, [(leg: 1, n: 0)]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('the planned way picks the journey itself', (tester) async {
    final picked = await _open(tester);

    await tester.tap(find.text('38').first);
    await tester.pumpAndSettle();

    expect(picked, [null]);
  });

  testWidgets('a way that could not be drawn says why and stays open', (
    tester,
  ) async {
    final picked = await _open(tester, failure: txt.searchAgain);

    await tester.tap(find.text(clockTime(1400)));
    await tester.pumpAndSettle();

    expect(picked, [(leg: 1, n: 1)]);
    expect(find.text(txt.searchAgain), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
