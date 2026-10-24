import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/home.dart';
import 'package:commuterlviv/src/map_theme.dart';
import 'package:commuterlviv/src/strings.dart';

import 'real_server.dart';

const _here = MethodChannel('nl.r1a.commuterlviv/here');
const _fixes = EventChannel('nl.r1a.commuterlviv/here/fixes');

/// A Pixel 6, as the app is laid out for
const _phone = Size(411, 914);

/// Long enough for the planner to have slid open
const _open = Duration(seconds: 1);

/// How long after it is built the map's tile layer first trims its caches, a
/// timer it does not cancel when it goes
const _firstTrim = Duration(seconds: 3);

/// A city of no stops, a user of no sets, and a basemap of nothing - all the
/// home screen needs to come up. The socket is refused, which it retries.
Future<HttpServer> _serve() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) {
    final body = switch (req.uri.path) {
      '/api/catalog' => {'routes': [], 'stops': []},
      '/api/me' => {
        'username': 'me',
        'sets': {'sets': [], 'active': null},
      },
      // One source drawn, or the map is refused; its tiles are never there
      final p when p.endsWith('/style.json') => {
        'version': 8,
        'name': 'nothing',
        'sources': {
          'none': {
            'type': 'vector',
            'tiles': [
              'http://${req.headers.host}:${req.connectionInfo!.localPort}/tiles/{z}/{x}/{y}',
            ],
          },
        },
        'layers': [
          {
            'id': 'none',
            'type': 'fill',
            'source': 'none',
            'source-layer': 'none',
            'paint': {'fill-color': '#000000'},
          },
        ],
      },
      _ => null,
    };
    if (body == null) req.response.statusCode = HttpStatus.notFound;
    // Closed after each answer, or the client's idle timer outlives the test
    req.response
      ..persistentConnection = false
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body ?? {}));
    req.response.close();
  });
  return server;
}

void main() {
  testWidgets('an end put where I am reads so in the planner, not as its '
      'coordinates', (tester) async {
    useLang(Lang.en);
    addTearDown(() => useLang(Lang.uk));
    // The test font draws every glyph a square, wider than the tab bar sizes
    // its tabs for; in the real font they fit
    final reported = FlutterError.onError!;
    FlutterError.onError = (e) {
      if (!e.exceptionAsString().contains('RenderFlex overflowed')) reported(e);
    };
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    allowRealHttp();
    final server = (await tester.runAsync(_serve))!;
    addTearDown(() => server.close(force: true));
    final origin = 'http://${server.address.host}:${server.port}';
    setTileOrigin(origin);
    addTearDown(() => setTileOrigin(null));
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_here, (_) async => true);
    addTearDown(() => messenger.setMockMethodCallHandler(_here, null));
    MockStreamHandlerEventSink? fixes;
    messenger.setMockStreamHandler(
      _fixes,
      MockStreamHandler.inline(
        onListen: (_, sink) {
          fixes = sink;
        },
      ),
    );
    addTearDown(() => messenger.setMockStreamHandler(_fixes, null));
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final api = await Api.open();
    await api.setBase(origin);

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(api: api, username: 'me', onOut: () {}),
      ),
    );
    // Four tabs are compact: one not picked is named by its tooltip only
    await pumpUntil(tester, () => tester.any(find.byTooltip(txt.plan)));
    await tester.tap(find.byTooltip(txt.plan));
    await tester.pump(_open);
    // Pressed rather than tapped: the map's own buttons float over the
    // panel's corner on the test surface
    tester
        .widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.my_location).first,
        )
        .onPressed!();
    await tester.pump(_open);
    fixes!.success({'lat': 49.8419, 'lon': 24.0315, 'accuracy': 5.0, 't': 0.0});
    // Not settled: the dot where I am pulses for as long as it is drawn
    await tester.pump();

    expect(find.widgetWithText(OutlinedButton, txt.useHere), findsOneWidget);
    expect(find.textContaining('49.8419'), findsNothing);
    await tester.pump(_firstTrim);
    FlutterError.onError = reported;
  });
}
