import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/sheets.dart';
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

/// A bus and a tram, for the grouping under vehicle types
const _mixed = Catalog(
  routes: [
    TransitRoute(id: 'b1', short: 'А01', long: 'A to B', type: 'bus'),
    TransitRoute(id: 't1', short: 'Т01', long: 'C to D', type: 'tram'),
  ],
  stops: [],
  index: {'b1': 0, 't1': 1},
  stopIndex: {},
);

/// The sheet over [catalog] with [sets], opening a line with [onRoute].
Future<void> _pump(
  WidgetTester tester, {
  Catalog catalog = _catalog,
  Sets? sets,
  Set<int> picked = const {},
  String? server,
  void Function(int route)? onRoute,
}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final api = (await tester.runAsync(Api.open))!;
  if (server != null) await tester.runAsync(() => api.setBase(server));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RouteSheet(
          api: api,
          catalog: catalog,
          sets: sets,
          picked: picked,
          onToggle: (_) {},
          onClear: () {},
          onActivated: (_, _) {},
          onSets: (_) {},
          onRoute: onRoute ?? (_) {},
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
      greaterThan(tester.getTopLeft(find.byType(FilterChip).first).dy),
    );

    await tester.enterText(find.byType(TextField), 'C to');
    await tester.pump();
    expect(find.text(txt.kinds['bus']!), findsNothing);
    expect(find.byType(FilterChip), findsOneWidget);
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

  testWidgets('the route sheet opens a line on a long press', (tester) async {
    var opened = -1;
    await _pump(tester, onRoute: (i) => opened = i);
    await tester.longPress(find.widgetWithText(FilterChip, '48'));
    await tester.pumpAndSettle();
    expect(opened, 0);
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
}
