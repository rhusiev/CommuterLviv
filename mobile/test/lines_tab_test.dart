import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/here.dart';
import 'package:commuterlviv/src/lines_tab.dart';
import 'package:commuterlviv/src/live.dart';
import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/route_badge.dart';
import 'package:commuterlviv/src/route_chip.dart';
import 'package:commuterlviv/src/strings.dart';

import 'real_server.dart';

/// A chip's tooltip is shown on a long press and wins the gesture arena, so a
/// tooltip here would stop the line ever opening.
const _catalog = Catalog(
  routes: [TransitRoute(id: 'r48', short: '48', long: 'A to B', type: 'bus')],
  stops: [],
  index: {'r48': 0},
  stopIndex: {},
);

/// A bus and a tram, for the grouping under vehicle types; only the bus calls
/// near [_atLat], [_atLon]
const _atLat = 49.84;
const _atLon = 24.03;
const _mixed = Catalog(
  routes: [
    TransitRoute(id: 'b1', short: 'А01', long: 'A to B', type: 'bus'),
    TransitRoute(id: 't1', short: 'Т01', long: 'C to D', type: 'tram'),
  ],
  stops: [
    Stop(id: 'a', name: 'A', code: '', lat: _atLat, lon: _atLon, routes: [0]),
    Stop(id: 'c', name: 'C', code: '', lat: 49.9, lon: 24.1, routes: [1]),
  ],
  index: {'b1': 0, 't1': 1},
  stopIndex: {'a': 0, 'c': 1},
);

/// The grid's chip for route [id]; a badge drops the letter of the number
Finder _chip(String id) => find.ancestor(
  of: find.byWidgetPredicate((w) => w is RouteBadge && w.route.id == id),
  matching: find.byType(RouteChip),
);

/// A `Here` whose platform side says yes and hands out fixes through the sink.
({Here here, MockStreamHandlerEventSink? Function() sink}) _here(
  WidgetTester tester,
) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('nl.r1a.commuterlviv/here'),
    (_) async => true,
  );
  MockStreamHandlerEventSink? sink;
  messenger.setMockStreamHandler(
    const EventChannel('nl.r1a.commuterlviv/here/fixes'),
    MockStreamHandler.inline(
      onListen: (_, events) {
        sink = events;
      },
    ),
  );
  return (here: Here(onFirstFix: (_) {}), sink: () => sink);
}

/// The tab over [catalog] with [sets], opening a line with [onOpen]. The sets
/// it is told of are handed back to it, as the home screen does.
Future<void> _pump(
  WidgetTester tester, {
  Catalog catalog = _catalog,
  Sets? sets,
  Set<int> picked = const {},
  List<String> recent = const [],
  String? server,
  Here? here,
  void Function(int route)? onOpen,
}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final api = (await tester.runAsync(Api.open))!;
  if (server != null) await tester.runAsync(() => api.setBase(server));
  var held = sets;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => LinesTab(
            api: api,
            catalog: catalog,
            sets: held,
            picked: picked,
            onToggle: (_) {},
            onClear: () {},
            onActivated: (_, _) {},
            onSets: (sets) => setState(() => held = sets),
            onOpen: onOpen ?? (_) {},
            recent: recent,
            here: here ?? Here(onFirstFix: (_) {}),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _made = {
  'id': 'set-1',
  'name': 'home',
  'routes': ['r48'],
  'ord': 0,
};

/// Makes a set as asked but refuses to activate it, listing what it made.
Future<HttpServer> _refusingActivation() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final made = <Object>[];
  server.listen((req) {
    final asked = (req.method, req.uri.path);
    if (asked == ('POST', '/api/sets')) made.add(_made);
    final (status, body) = switch (asked) {
      ('POST', '/api/sets') => (HttpStatus.ok, _made),
      ('POST', '/api/sets/active') => (
        HttpStatus.internalServerError,
        {'error': 'down'},
      ),
      _ => (
        HttpStatus.ok,
        {'sets': made, 'active': null, 'pins': [], 'places': []},
      ),
    };
    // A kept connection's idle timer would outlive the test's fake clock
    req.response
      ..persistentConnection = false
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body))
      ..close();
  });
  return server;
}

void main() {
  testWidgets('routes are grouped under their vehicle type', (tester) async {
    await _pump(tester, catalog: _mixed);
    expect(find.text(txt.kinds['bus']!), findsOneWidget);
    expect(find.text(txt.kinds['tram']!), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(txt.kinds['tram']!)).dy,
      greaterThan(tester.getTopLeft(find.byType(RouteChip).first).dy),
    );

    await tester.enterText(find.byType(TextField), 'C to');
    await tester.pump();
    expect(find.text(txt.kinds['bus']!), findsNothing);
    expect(find.byType(RouteChip), findsOneWidget);
  });

  testWidgets('a screen reader hears each vehicle type as its own heading', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, catalog: _mixed);
    for (final kind in ['bus', 'tram']) {
      expect(
        tester.getSemantics(find.text(txt.kinds[kind]!)),
        isSemantics(label: txt.kinds[kind]!, isHeader: true),
      );
    }
    semantics.dispose();
  });

  testWidgets('a route opens its line from its chip\'s chevron only', (
    tester,
  ) async {
    var opened = -1;
    await _pump(tester, onOpen: (i) => opened = i);
    await tester.longPress(find.text('48'));
    await tester.pumpAndSettle();
    expect(opened, -1);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(opened, 0);
  });

  testWidgets('watching lists only the routes watched', (tester) async {
    await _pump(tester, catalog: _mixed, picked: {1});

    await tester.tap(find.text(txt.watchingLines(1)));
    await tester.pumpAndSettle();

    expect(_chip('t1'), findsOneWidget);
    expect(_chip('b1'), findsNothing);
  });

  testWidgets('watching nothing says so', (tester) async {
    await _pump(tester, catalog: _mixed);

    await tester.tap(find.text(txt.watchingLines(0)));
    await tester.pumpAndSettle();

    expect(find.text(txt.noneWatched), findsOneWidget);
    expect(find.byType(RouteChip), findsNothing);
  });

  testWidgets('near me asks for a fix and lists the routes calling near it', (
    tester,
  ) async {
    final (:here, :sink) = _here(tester);
    await _pump(tester, catalog: _mixed, here: here);

    await tester.tap(find.text(txt.nearLines));
    await tester.pumpAndSettle();
    expect(find.text(txt.locating), findsOneWidget);

    sink()!.success({'lat': _atLat, 'lon': _atLon, 'accuracy': 10.0, 't': 0.0});
    await tester.pumpAndSettle();
    expect(find.text(txt.locating), findsNothing);
    expect(_chip('b1'), findsOneWidget);
    expect(_chip('t1'), findsNothing);
  });

  testWidgets('a line opened lately is offered again', (tester) async {
    var opened = -1;
    await _pump(
      tester,
      catalog: _mixed,
      recent: ['t1'],
      onOpen: (i) => opened = i,
    );

    await tester.tap(find.widgetWithText(ListTile, 'C to D'));
    expect(opened, 1);
  });

  testWidgets('a set the server refuses to show says why', (tester) async {
    // The test binding answers every request 400
    await _pump(
      tester,
      sets: const Sets(
        sets: [
          RouteSet(id: 'set-1', name: 'home', routes: ['r48'], ord: 0),
        ],
        active: null,
        pins: [],
        places: [],
      ),
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'home'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('The server said 400'), findsOneWidget);
  });

  testWidgets('a set made but not activated is listed, saying why', (
    tester,
  ) async {
    allowRealHttp();
    final server = (await tester.runAsync(_refusingActivation))!;
    addTearDown(() => server.close(force: true));
    await _pump(
      tester,
      picked: {0},
      server: 'http://${server.address.host}:${server.port}',
    );

    await tester.tap(find.text(txt.saveAsSet));
    await tester.pumpAndSettle();
    final dialog = find.byType(Dialog);
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)),
      'home',
    );
    await tester.tap(
      find.descendant(of: dialog, matching: find.text(txt.save)),
    );
    await pumpUntil(tester, () => tester.any(find.text('down')));

    expect(find.widgetWithText(ChoiceChip, 'home'), findsOneWidget);
  });

  testWidgets(
    'a line lists its stops one way, with the bus due and where it is',
    (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      const minute = 60;
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final api = (await tester.runAsync(Api.open))!;
      final live = Live(api, onRenewed: () {})
        ..arrivals = {
          1: [Arrival(route: 0, veh: 7, t: now + 5 * minute)],
        };
      var way = 0;
      int? stop;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => LinePanel(
                catalog: _mixed,
                live: live,
                route: 0,
                ways: const [
                  (dir: 0, stops: [0, 1]),
                  (dir: 1, stops: [1, 0]),
                ],
                way: way,
                onWay: (w) => setState(() => way = w),
                watching: false,
                onWatch: () {},
                onStop: (s) => stop = s,
                onBack: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('→ C'), findsOneWidget);
      expect(find.text(txt.minutes(5)), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('A')).dy,
        lessThan(tester.getTopLeft(find.text('C')).dy),
      );
      expect(find.bySemanticsLabel(RegExp(txt.vehicleHere)), findsOneWidget);
      final vehicle = find.byWidgetPredicate(
        (w) => w is Icon && w.semanticLabel == txt.vehicleHere,
      );
      expect(
        tester.getCenter(vehicle).dy,
        closeTo(tester.getCenter(find.text('C')).dy, 8),
      );

      await tester.tap(find.text('→ C'));
      await tester.pumpAndSettle();
      expect(find.text('→ A'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('C')).dy,
        lessThan(tester.getTopLeft(find.text('A')).dy),
      );

      await tester.tap(find.text('C'));
      expect(stop, 1);
      semantics.dispose();
    },
  );
}
