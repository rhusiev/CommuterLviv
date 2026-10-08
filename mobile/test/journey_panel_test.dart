import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
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
  String? server,
  Catalog catalog = const Catalog(
    routes: [],
    stops: [],
    index: {},
    stopIndex: {},
  ),
  LatLng? from,
  LatLng? to,
  void Function(Journey? journey)? onShow,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  FlutterSecureStorage.setMockInitialValues({});
  final api = await Api.open();
  if (server != null) await api.setBase(server);
  var folded = false;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => JourneyPanel(
            api: api,
            catalog: catalog,
            from: from,
            to: to,
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
            onShow: onShow ?? (_) {},
            onFollow: (_) {},
          ),
        ),
      ),
    ),
  );
}

const _twoLines = Catalog(
  routes: [
    TransitRoute(id: 'r8', short: '8', long: 'A to B', type: 'tram'),
    TransitRoute(id: 'r3', short: '3', long: 'C to D', type: 'tram'),
  ],
  stops: [
    Stop(id: 's0', name: 'Home stop', code: '0', lat: 0, lon: 0, routes: []),
    Stop(id: 's1', name: 'Work stop', code: '1', lat: 0, lon: 0, routes: []),
  ],
  index: {'r8': 0, 'r3': 1},
  stopIndex: {},
);

Map<String, Object> _ride(
  int route,
  int dep, {
  List<Object> backups = const [],
}) => {
  'kind': 'ride',
  'dep': dep,
  'arr': dep + 600,
  'a': 0,
  'b': 1,
  'route': route,
  'live': true,
  'backups': backups,
};

Map<String, Object> _journey(Map<String, Object> ride, {int backup = 0}) => {
  'dep': 0,
  'arr': (ride['arr']! as int) + 60,
  'rides': 1,
  'live': true,
  'confidence': 'live',
  'backup': backup,
  'legs': [
    {'kind': 'walk', 'dep': 0, 'arr': 60, 'a': -1, 'b': 0},
    ride,
    {
      'kind': 'walk',
      'dep': ride['arr']!,
      'arr': (ride['arr']! as int) + 60,
      'a': 1,
      'b': -1,
    },
  ],
};

/// Answers a search with one option backed by a ride that is no option of its
/// own, and that ride's way when asked for it, noting the asks.
Future<HttpServer> _serve(List<Uri> asked) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final later = _ride(1, 900);
  server.listen((req) {
    asked.add(req.uri);
    final body = switch (req.uri.path) {
      '/api/plan' => {
        't': 0,
        'report': 'r1',
        'options': [
          _journey(
            _ride(
              0,
              60,
              backups: [
                {
                  'rides': [later],
                  'arr': 1560,
                  'walk': 120,
                  'option': -1,
                },
              ],
            ),
            backup: 1,
          ),
        ],
      },
      _ => _journey(later),
    };
    // A kept connection's idle timer would outlive the test's fake clock
    req.response
      ..persistentConnection = false
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body))
      ..close();
  });
  return server;
}

/// Pumps, letting the fake server answer, until [done] says so.
Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
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

  test('a ride reads what it rests on, an unknown word as the timetable', () {
    expect(confidenceOf(null), Confidence.live);
    expect(confidenceOf('terminus'), Confidence.terminus);
    expect(confidenceOf('quiet'), Confidence.quiet);
    expect(confidenceOf('something newer'), Confidence.schedule);
  });

  test('only a ride resting on more than a tracked vehicle says so', () {
    expect(legNote(Confidence.live), isNull);
    expect(legNote(Confidence.terminus)?.$1, txt.terminusPart);
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

  testWidgets('a backup that is no option is fetched and drawn as one', (
    tester,
  ) async {
    // The test binding answers every request 400 unless let through
    final faked = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = faked);
    final asked = <Uri>[];
    final server = (await tester.runAsync(() => _serve(asked)))!;
    addTearDown(() => server.close(force: true));
    final shown = <Journey?>[];
    await pump(
      tester,
      server: 'http://${server.address.host}:${server.port}',
      catalog: _twoLines,
      from: const LatLng(49.84, 24.03),
      to: const LatLng(49.81, 24.05),
      onShow: shown.add,
    );

    await tester.tap(find.text(txt.findRoute));
    final backups = find.text('· ${txt.backupCount(1)}');
    await _until(tester, () => backups.evaluate().isNotEmpty);
    await tester.tap(backups);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(txt.showWay).last);
    await _until(tester, () => find.byType(AlertDialog).evaluate().isEmpty);

    expect(asked.last.path, '/api/backup');
    expect(asked.last.queryParameters, {
      'report': 'r1',
      'option': '0',
      'leg': '1',
      'backup': '0',
    });
    expect(shown.last?.legs[1].route, 1);
    expect(shown.last?.legs[1].dep, 900);
    expect(find.text(txt.findRoute), findsNothing);
  });
}
