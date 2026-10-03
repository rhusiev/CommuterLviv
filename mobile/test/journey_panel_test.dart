import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/journey_panel.dart';
import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/strings.dart';

Future<void> pump(
  WidgetTester tester, {
  End? picking,
  void Function(End? which)? onPick,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  FlutterSecureStorage.setMockInitialValues({});
  final api = await Api.open();
  var folded = false;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => JourneyPanel(
            api: api,
            catalog: const Catalog(
              routes: [],
              stops: [],
              index: {},
              stopIndex: {},
            ),
            from: null,
            to: null,
            picking: picking,
            onPick: onPick ?? (_) {},
            folded: folded,
            onFold: (to) => setState(() => folded = to),
            onSwap: () {},
            onHere: (_) {},
            onStop: (_) {},
            onLine: (_) {},
            places: const [],
            onSave: (_, _) {},
            onPlace: (_, _) {},
            onShow: (_) {},
            onFollow: (_) {},
          ),
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

    expect(find.byTooltip(txt.departAt), findsOneWidget);
    expect(find.text(txt.now), findsOneWidget);

    await tester.tap(find.text(txt.now));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
  });

  testWidgets('the day chip leaves today until a day is picked', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text(txt.today));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('a search walks at the usual speed, stepped for it alone', (
    tester,
  ) async {
    await pump(tester, prefs: {'commuterlviv.walk': 7.5});
    expect(find.text(txt.kmh(7.5)), findsOneWidget);

    await tester.tap(find.byTooltip(txt.faster));
    await tester.pump();
    expect(find.text(txt.kmh(8)), findsOneWidget);
    final faster = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.add),
    );
    expect(faster.onPressed, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('commuterlviv.walk'), 7.5);
  });

  testWidgets('a usual speed out of range is the service\'s own', (
    tester,
  ) async {
    await pump(tester, prefs: {'commuterlviv.walk': 30.0});
    expect(find.text(txt.kmh(walkKmh.usual)), findsOneWidget);
  });

  testWidgets('an end offers where I am and the map before a search', (
    tester,
  ) async {
    End? picked;
    await pump(tester, onPick: (end) => picked = end);

    await tester.tap(find.text(txt.findStop).last);
    await tester.pumpAndSettle();
    expect(find.text(txt.useHere), findsOneWidget);
    expect(find.text(txt.noPlaces), findsOneWidget);

    await tester.tap(find.text(txt.chooseOnMap));
    await tester.pumpAndSettle();
    expect(picked, End.to);
  });

  testWidgets('hiding the panel folds it to a strip that opens it again', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.byTooltip(txt.hidePanel));
    await tester.pump();
    expect(find.text(txt.findRoute), findsNothing);

    await tester.tap(find.byTooltip(txt.showPanel));
    await tester.pump();
    expect(find.text(txt.findRoute), findsOneWidget);
  });

  testWidgets('picking an end on the map folds the panel out of the way', (
    tester,
  ) async {
    await pump(tester, picking: End.from);
    expect(find.text(txt.findRoute), findsNothing);
    expect(find.text('${txt.from}: ${txt.tapMap}'), findsOneWidget);
  });

  test('a leg reads the line it is drawn along', () {
    final leg = Leg.fromJson({
      'kind': 'walk',
      'dep': 0,
      'arr': 60,
      'a': -1,
      'b': 3,
      'pts': [
        [49.8, 24.0],
        [49.81, 24.01],
      ],
    });
    expect(leg.pts.map((p) => (p.latitude, p.longitude)), [
      (49.8, 24.0),
      (49.81, 24.01),
    ]);
  });

  test('an arrival says whether it waits on the timetable', () {
    final at = {'route': 1, 'veh': 2, 't': 3};
    expect(Arrival.fromJson(at).planned, isFalse);
    expect(Arrival.fromJson({...at, 'planned': true}).planned, isTrue);
  });

  test('only a ride not on a tracked vehicle says what it rests on', () {
    expect(legNote(Confidence.live), isNull);
    expect(legNote(Confidence.schedule)?.$1, txt.schedulePart);
    expect(legNote(Confidence.quiet)?.$1, txt.quietPart);
  });

  test('a ride reads its backups, and an older service has none', () {
    const ride = {'kind': 'ride', 'dep': 0, 'arr': 60, 'a': 1, 'b': 2};
    expect(Leg.fromJson(ride).backups, isEmpty);
    final leg = Leg.fromJson({
      ...ride,
      'backups': [
        {
          'rides': [
            {
              'route': 4,
              'dep': 120,
              'arr': 300,
              'a': 1,
              'b': 3,
              'live': true,
              'planned': false,
            },
            {
              'route': 5,
              'dep': 400,
              'arr': 600,
              'a': 3,
              'b': 2,
              'live': false,
              'planned': true,
            },
          ],
          'arr': 700,
          'walk': 90,
          'option': 2,
        },
      ],
    });
    final backup = leg.backups.single;
    expect(backup.rides.map((r) => (r.route, r.dep, r.a, r.b, r.live)), [
      (4, 120, 1, 3, true),
      (5, 400, 3, 2, false),
    ]);
    expect(backup.arr, 700);
    expect(backup.walk, 90);
    expect(backup.planned, [false, true]);
    expect(backup.option, 2);
    expect(const Backup(rides: [], arr: 0).option, -1);
  });

  test('backups shortlist the best by what is preferred and by the rest', () {
    Leg ride(int dep, {bool live = true}) =>
        Leg(kind: 'ride', dep: dep, arr: dep, a: 0, b: 0, live: live);
    Backup way(int dep, int arr, int rides, int walk, [bool planned = false]) =>
        Backup(
          rides: [for (var i = 0; i < rides; i++) ride(dep)],
          arr: arr,
          walk: walk,
          planned: [planned, for (var i = 1; i < rides; i++) false],
        );
    final soonest = way(100, 900, 2, 60);
    final direct = way(200, 1000, 1, 300);
    final dry = way(300, 1100, 2, 0);
    final mine = way(400, 800, 1, 120, true);
    final late = way(500, 1200, 1, 60);
    final all = [soonest, direct, dry, mine, late];
    // The best by fewest changes, by walking and by not riding the plan's
    // vehicles, then the next by fewest changes, kept in the order they leave
    expect(Prefer.changes.shortlist(all), [soonest, dry, mine, late]);
    expect(Prefer.fastest.shortlist(all, n: 2), [dry, mine]);
    expect(Prefer.reliable.shortlist(all, n: 1), [soonest]);
    expect(Prefer.walk.shortlist(all, n: 9), all);
  });
}
