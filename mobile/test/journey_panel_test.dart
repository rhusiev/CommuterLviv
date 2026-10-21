import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/hurry_pill.dart';
import 'package:commuterlviv/src/journey_panel.dart';
import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/route_badge.dart';
import 'package:commuterlviv/src/strings.dart';

import 'real_server.dart';

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
  Aboard? aboard,
  LatLng? to,
  Map<LatLng, String> named = const {},
  void Function(Journey? journey)? onShow,
  void Function(int stop)? onStop,
  void Function(int route)? onLine,
  bool ask = false,
  VoidCallback? onAsked,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  FlutterSecureStorage.setMockInitialValues({});
  final api = await Api.open();
  if (server != null) await api.setBase(server);
  var folded = false;
  var asking = ask;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => JourneyPanel(
            api: api,
            catalog: catalog,
            from: from,
            aboard: aboard,
            to: to,
            picking: picking,
            onPick: onPick ?? (_) {},
            folded: folded,
            onFold: (to) => setState(() => folded = to),
            onSwap: () {},
            onHere: (_) {},
            onStop: onStop ?? (_) {},
            onLine: onLine ?? (_) {},
            places: const [],
            named: named,
            onSave: (_, _) {},
            onPlace: (_, _) {},
            onShow: onShow ?? (_) {},
            onFollow: (_) {},
            ask: asking,
            onAsked: () => setState(() {
              asking = false;
              onAsked?.call();
            }),
          ),
        ),
      ),
    ),
  );
}

/// A walk of 45 m north: hurried to a ride leaving 60 s after it sets off, with
/// half a minute to spare, it takes 5.4 km/h
const _walk45m = [
  [49.84, 24.03],
  [49.84 + 45 / 111195, 24.03],
];

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
  String confidence = 'live',
}) => {
  'kind': 'ride',
  'dep': dep,
  'arr': dep + 600,
  'a': 0,
  'b': 1,
  'route': route,
  'live': true,
  'confidence': confidence,
  'backups': backups,
};

Map<String, Object> _journey(
  Map<String, Object> ride, {
  int backup = 0,
  bool hurry = false,
  List<List<double>> walk = const [],
}) => {
  'dep': 0,
  'hurry': hurry,
  'arr': (ride['arr']! as int) + 60,
  'rides': 1,
  'live': true,
  'confidence': 'live',
  'backup': backup,
  'legs': [
    {'kind': 'walk', 'dep': 0, 'arr': 60, 'a': -1, 'b': 0, 'pts': walk},
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

/// Answers a search with one option, riding [route], backed by a ride that is
/// no option of its own, and that ride's way when asked for it, noting the asks.
Future<HttpServer> _serve(
  List<Uri> asked, {
  int route = 0,
  String confidence = 'live',
}) async {
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
              route,
              60,
              confidence: confidence,
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
            hurry: true,
            walk: _walk45m,
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

  testWidgets('a hurrying speed is sent once set, and flags an option', (
    tester,
  ) async {
    allowRealHttp();
    final asked = <Uri>[];
    final server = (await tester.runAsync(() => _serve(asked)))!;
    addTearDown(() => server.close(force: true));
    await pump(
      tester,
      prefs: {'commuterlviv.hurry': 9.0},
      server: 'http://${server.address.host}:${server.port}',
      catalog: _twoLines,
      from: const LatLng(49.84, 24.03),
      to: const LatLng(49.81, 24.05),
    );

    await tester.tap(find.text(txt.findRoute));
    final pill = find.widgetWithText(HurryPill, txt.hurryAt(txt.kmh(5.5)));
    await pumpUntil(tester, () => tester.any(pill));

    expect(asked.single.queryParameters['hurry'], '9.0');
    expect(pill, findsOneWidget);
  });

  testWidgets('an end chosen outside the panel reads by its name there', (
    tester,
  ) async {
    const rynok = LatLng(49.8419, 24.0315);
    await pump(tester, to: rynok, named: {rynok: 'Rynok'});

    expect(find.text('Rynok'), findsOneWidget);
    expect(find.textContaining('49.8419'), findsNothing);
  });

  testWidgets('an end offers where I am and the map before a search', (
    tester,
  ) async {
    End? picked;
    await pump(tester, onPick: (end) => picked = end);

    await tester.tap(find.text(txt.to));
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

  /// Searches against [_serve], with the one option it answers not yet picked
  Future<List<Journey?>> searched(
    WidgetTester tester, {
    String confidence = 'live',
    void Function(int stop)? onStop,
    void Function(int route)? onLine,
  }) async {
    allowRealHttp();
    final server = (await tester.runAsync(
      () => _serve([], confidence: confidence),
    ))!;
    addTearDown(() => server.close(force: true));
    final shown = <Journey?>[];
    await pump(
      tester,
      server: 'http://${server.address.host}:${server.port}',
      catalog: _twoLines,
      from: const LatLng(49.84, 24.03),
      to: const LatLng(49.81, 24.05),
      onShow: shown.add,
      onStop: onStop,
      onLine: onLine,
    );
    await tester.tap(find.text(txt.findRoute));
    await pumpUntil(tester, () => find.text('Work stop').evaluate().isNotEmpty);
    expect(shown.whereType<Journey>(), isEmpty);
    return shown;
  }

  testWidgets("a ride's note explains itself once its option is picked", (
    tester,
  ) async {
    final shown = await searched(tester, confidence: 'terminus');
    final info = find.byIcon(Icons.info_outline);
    expect(info, findsNothing);

    await tester.tap(find.text(txt.terminusPart));
    await tester.pumpAndSettle();
    expect(find.text(txt.terminusWhy), findsNothing);
    expect(shown.last, isNotNull);
    expect(info, findsWidgets);

    await tester.tap(find.text(txt.terminusPart));
    await tester.pumpAndSettle();
    expect(find.text(txt.terminusWhy), findsOneWidget);
  });

  testWidgets("a ride's line opens once its option is picked", (tester) async {
    final lines = <int>[];
    final shown = await searched(tester, onLine: lines.add);

    await tester.tap(find.byType(RouteBadge));
    await tester.pump();
    expect(lines, isEmpty);
    expect(shown.last, isNotNull);

    await tester.tap(find.byType(RouteBadge));
    await tester.pump();
    expect(lines, [0]);
  });

  testWidgets('a stop opens once its option is picked, as its chevron says', (
    tester,
  ) async {
    final stops = <int>[];
    final shown = await searched(tester, onStop: stops.add);
    final chevron = find.byIcon(Icons.chevron_right);
    expect(chevron, findsNothing);

    await tester.tap(find.text('Work stop'));
    await tester.pump();
    expect(stops, isEmpty);
    expect(shown.last, isNotNull);
    expect(chevron, findsWidgets);

    await tester.tap(find.text('Work stop'));
    await tester.pump();
    expect(stops, [1]);
  });

  testWidgets('the hurry pill says why once its option is picked', (
    tester,
  ) async {
    allowRealHttp();
    final server = (await tester.runAsync(() => _serve([])))!;
    addTearDown(() => server.close(force: true));
    await pump(
      tester,
      prefs: {'commuterlviv.hurry': 9.0},
      server: 'http://${server.address.host}:${server.port}',
      catalog: _twoLines,
      from: const LatLng(49.84, 24.03),
      to: const LatLng(49.81, 24.05),
    );
    await tester.tap(find.text(txt.findRoute));
    final pill = find.byType(HurryPill);
    await pumpUntil(tester, () => tester.any(pill));
    final why = find.text('${txt.hurryHint}. ${txt.paceHint}');

    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(why, findsNothing);

    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(why, findsOneWidget);
  });

  testWidgets('a backup that is no option is fetched and drawn as one', (
    tester,
  ) async {
    // The test binding answers every request 400 unless let through
    allowRealHttp();
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
    await pumpUntil(tester, () => backups.evaluate().isNotEmpty);
    // The first tap picks the option, the second opens its backups
    await tester.tap(backups);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(backups);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(txt.showWay).last);
    await pumpUntil(tester, () => find.byType(AlertDialog).evaluate().isEmpty);

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

  testWidgets('a ride on a line the catalog lacks is shown without its badge', (
    tester,
  ) async {
    allowRealHttp();
    final server = (await tester.runAsync(() => _serve([], route: -1)))!;
    addTearDown(() => server.close(force: true));
    await pump(
      tester,
      server: 'http://${server.address.host}:${server.port}',
      catalog: _twoLines,
      from: const LatLng(49.84, 24.03),
      to: const LatLng(49.81, 24.05),
    );

    await tester.tap(find.text(txt.findRoute));
    final backups = find.text('· ${txt.backupCount(1)}');
    await pumpUntil(tester, () => backups.evaluate().isNotEmpty);
    // The first tap picks the option, the second opens its backups
    await tester.tap(backups);
    await tester.pump();
    await tester.tap(backups);
    await tester.pumpAndSettle();

    // the backup rides line 3; the planned ride's line is unknown
    expect(find.widgetWithText(RouteBadge, '3'), findsWidgets);
    expect(find.widgetWithText(RouteBadge, '8'), findsNothing);
  });

  testWidgets('on board, a search sends the vehicle alone and leaves now', (
    tester,
  ) async {
    allowRealHttp();
    final asked = <Uri>[];
    final server = (await tester.runAsync(() => _serve(asked)))!;
    addTearDown(() => server.close(force: true));
    await pump(
      tester,
      server: 'http://${server.address.host}:${server.port}',
      catalog: _twoLines,
      aboard: const Aboard(12, 1),
      to: const LatLng(49.81, 24.05),
    );

    expect(find.text(txt.aboard), findsOneWidget);
    expect(find.text(txt.now), findsNothing);
    final swap = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.swap_vert),
    );
    expect(swap.onPressed, isNull);

    await tester.tap(find.text(txt.findRoute));
    await pumpUntil(tester, () => asked.isNotEmpty);

    expect(asked.single.path, '/api/plan');
    expect(asked.single.queryParameters.keys.toSet(), {'veh', 'to', 'speed'});
    expect(asked.single.queryParameters['veh'], '12');
  });

  testWidgets('a search asked for runs once, as soon as both ends are set', (
    tester,
  ) async {
    allowRealHttp();
    final asked = <Uri>[];
    var told = 0;
    final server = (await tester.runAsync(() => _serve(asked)))!;
    addTearDown(() => server.close(force: true));
    Future<void> ask(LatLng? to) => pump(
      tester,
      server: 'http://${server.address.host}:${server.port}',
      catalog: _twoLines,
      aboard: const Aboard(12, 1),
      to: to,
      ask: true,
      onAsked: () => told++,
    );

    await ask(null);
    await pumpQuiet(tester);
    expect(asked, isEmpty);
    expect(told, 0);

    await ask(const LatLng(49.81, 24.05));
    await pumpUntil(tester, () => asked.isNotEmpty);
    await pumpQuiet(tester);

    expect(asked.single.path, '/api/plan');
    expect(told, 1);
  });
}
