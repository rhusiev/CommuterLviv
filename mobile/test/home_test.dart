import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/home.dart';
import 'package:commuterlviv/src/lines_tab.dart' show LinePanel;
import 'package:commuterlviv/src/map_tab.dart' show lviv;
import 'package:commuterlviv/src/map_theme.dart';
import 'package:commuterlviv/src/models.dart';
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

/// A city of [catalog], no stops by default, its lines of [shapes], a user of
/// no sets and of [places], a basemap of nothing, and [plan] for any search -
/// all the home screen needs to come up. Places written are taken as
/// they come, and each list written is added to [sent]. The socket is refused,
/// which it retries.
Future<HttpServer> _serve({
  List<Place> places = const [],
  List<Object?>? sent,
  Map<String, Object?> catalog = _noCatalog,
  Map<String, Object?> shapes = _noShapes,
  Map<String, Object?>? plan,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final body = switch (req.uri.path) {
      '/api/catalog' => catalog,
      '/api/shapes' => shapes,
      '/api/plan' => plan,
      '/api/me' => {
        'username': 'me',
        'sets': {
          'sets': [],
          'active': null,
          'places': [for (final p in places) p.toJson()],
        },
      },
      '/api/places' => _noted(jsonDecode(await utf8.decodeStream(req)), sent),
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

/// What was [written], its list of places added to [sent].
Object? _noted(Object? written, List<Object?>? sent) {
  sent?.add((written as Map<String, dynamic>)['places']);
  return written;
}

/// The home screen on a phone, signed in to [_serve], once it has come up.
Future<void> _pumpHome(
  WidgetTester tester, {
  List<Place> places = const [],
  List<Object?>? sent,
  Map<String, Object?> catalog = _noCatalog,
  Map<String, Object?> shapes = _noShapes,
  Map<String, Object?>? plan,
}) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  allowRealHttp();
  final server = (await tester.runAsync(
    () => _serve(
      places: places,
      sent: sent,
      catalog: catalog,
      shapes: shapes,
      plan: plan,
    ),
  ))!;
  addTearDown(() => server.close(force: true));
  final origin = 'http://${server.address.host}:${server.port}';
  setTileOrigin(origin);
  addTearDown(() => setTileOrigin(null));
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
    await _pumpHome(tester);
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

  testWidgets('the map buttons under the open journey panel are not read out', (
    tester,
  ) async {
    useLang(Lang.en);
    addTearDown(() => useLang(Lang.uk));
    final reported = FlutterError.onError!;
    FlutterError.onError = (e) {
      if (!e.exceptionAsString().contains('RenderFlex overflowed')) reported(e);
    };
    final semantics = tester.ensureSemantics();
    await _pumpHome(tester);
    final zoomIn = find.semantics.byPredicate(
      (node) => node.tooltip == txt.zoomIn,
    );
    expect(zoomIn, findsOne);

    await tester.tap(find.byTooltip(txt.plan));
    await tester.pump(_open);
    expect(zoomIn, findsNothing);

    await tester.tap(find.byTooltip(txt.hidePanel));
    await tester.pump(_open);
    expect(zoomIn, findsOne);
    // The map's tile workers fail what they still hold when the map goes
    await pumpQuiet(tester);
    semantics.dispose();
    await _done(tester, reported);
  });

  testWidgets('the map buttons under an open line are not read out', (
    tester,
  ) async {
    useLang(Lang.en);
    addTearDown(() => useLang(Lang.uk));
    final reported = FlutterError.onError!;
    FlutterError.onError = (e) {
      if (!e.exceptionAsString().contains('RenderFlex overflowed')) reported(e);
    };
    final semantics = tester.ensureSemantics();
    await _pumpHome(tester, catalog: _lineCatalog, shapes: _lineShapes);
    final zoomIn = find.semantics.byPredicate(
      (node) => node.tooltip == txt.zoomIn,
    );

    await tester.tap(find.byTooltip(txt.lines));
    await tester.pump(_open);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await pumpUntil(tester, () => tester.any(find.text(_lineStop(0))));
    expect(zoomIn, findsNothing);

    await tester.tap(
      find.byTooltip(
        MaterialLocalizations.of(tester.element(find.byType(LinePanel)))
            .backButtonTooltip,
      ),
    );
    await tester.pump(_open);
    await tester.tap(find.byTooltip(txt.map));
    await tester.pump(_open);
    expect(zoomIn, findsOne);
    // The map's tile workers fail what they still hold when the map goes
    await pumpQuiet(tester);
    semantics.dispose();
    await _done(tester, reported);
  });

  testWidgets('an option opened frames the map on it', (tester) async {
    useLang(Lang.en);
    addTearDown(() => useLang(Lang.uk));
    final reported = FlutterError.onError!;
    FlutterError.onError = (e) {
      if (!e.exceptionAsString().contains('RenderFlex overflowed')) reported(e);
    };
    await _pumpHome(tester, places: _ends, catalog: _lineCatalog, plan: _plan);
    final map = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .mapController!;
    await tester.tap(find.byTooltip(txt.plan));
    await tester.pump(_open);
    for (final (i, end) in _ends.indexed) {
      // The search page slides in from the frame after the tap
      await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.search).at(i));
      await tester.pump();
      await tester.pump(_open);
      await tester.tap(find.text(end.name));
      await tester.pump();
      await tester.pump(_open);
    }
    await tester.tap(find.text(txt.findRoute));
    await pumpUntil(tester, () => tester.any(_optionLength));

    await tester.tap(_optionLength);
    await tester.pump();

    final middle =
        (_lineStopAt(0).longitude + _lineStopAt(_alighting).longitude) / 2;
    expect(map.camera.center.longitude, closeTo(middle, _sameDeg));
    // The map's tile workers fail what they still hold when the map goes
    await pumpQuiet(tester);
    await _done(tester, reported);
  });

  testWidgets('saving a point under a name in use elsewhere asks first, and '
      'a cancel sends nothing', (tester) async {
    final (sent, reported) = await _pumpWithHome(
      tester,
      const LatLng(49.8, 24.0),
    );
    await _saveHeld(tester, 'Home');

    expect(find.text(txt.placeNameTaken), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, txt.cancel));
    await pumpQuiet(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(sent, isEmpty);
    await _done(tester, reported);
  });

  testWidgets('saving a point under a name in use elsewhere replaces that '
      'place once confirmed', (tester) async {
    final (sent, reported) = await _pumpWithHome(
      tester,
      const LatLng(49.8, 24.0),
    );
    await _saveHeld(tester, 'Home');

    await tester.tap(find.widgetWithText(TextButton, txt.replace));
    await pumpUntil(tester, () => sent.isNotEmpty);
    expect(sent.single, [Place(name: 'Home', at: lviv).toJson()]);
    await _done(tester, reported);
  });

  testWidgets('saving a place again where it stands neither asks nor says '
      'anything', (tester) async {
    final (sent, reported) = await _pumpWithHome(tester, lviv);
    await _saveHeld(tester, 'Home');

    await pumpUntil(tester, () => sent.isNotEmpty);
    expect(find.byType(AlertDialog), findsNothing);
    expect(sent.single, [Place(name: 'Home', at: lviv).toJson()]);
    await pumpQuiet(tester);
    expect(find.byType(SnackBar), findsNothing);
    await _done(tester, reported);
  });
}

/// The home screen in English, of one place, "Home", at [at]; the lists of
/// places it writes, and the error handler to put back in [_done]. The test
/// font overflows the tab bar, which is let pass until then.
Future<(List<Object?>, void Function(FlutterErrorDetails))> _pumpWithHome(
  WidgetTester tester,
  LatLng at,
) async {
  useLang(Lang.en);
  addTearDown(() => useLang(Lang.uk));
  final reported = FlutterError.onError!;
  FlutterError.onError = (e) {
    if (!e.exceptionAsString().contains('RenderFlex overflowed')) reported(e);
  };
  final sent = <Object?>[];
  await _pumpHome(
    tester,
    places: [Place(name: 'Home', at: at)],
    sent: sent,
  );
  return (sent, reported);
}

/// Saves [lviv] under [name] from the sheet a long press opens there.
Future<void> _saveHeld(WidgetTester tester, String name) async {
  // Held through the map's own callback: the floating chrome covers much
  // of the test surface
  tester.widget<FlutterMap>(find.byType(FlutterMap)).options.onLongPress!(
    const TapPosition(Offset.zero, null),
    lviv,
  );
  await tester.pump();
  await tester.pump(_open);
  await tester.tap(find.text(txt.savePlaceAs));
  await tester.pump();
  await tester.enterText(find.byType(TextField), name);
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, txt.saveHere));
  await tester.pump();
  await tester.pump(_open);
}

/// Past the map's first cache trim, which outlives the test otherwise, with
/// the error handler [reported] put back.
Future<void> _done(
  WidgetTester tester,
  void Function(FlutterErrorDetails) reported,
) async {
  await tester.pump(_firstTrim);
  FlutterError.onError = reported;
}

const _noCatalog = <String, Object?>{'routes': [], 'stops': []};
const _noShapes = <String, Object?>{'routes': []};

/// How many stops the one line calls at: as many as a short city line, so its
/// panel is as tall as it gets
const _lineStops = 12;

String _lineStop(int i) => 'Stop $i';

/// Where the line's stop [i] stands: a step east of the one before, from the
/// west edge of the map's first view
LatLng _lineStopAt(int i) => LatLng(
  lviv.latitude,
  lviv.longitude + (i - (_lineStops - 1) / 2) * _lineStep,
);

/// Between two of the line's stops, in degrees of longitude: about 330 m. The
/// line then spans the map's first view, so framing it renders no new tiles,
/// which would still be rendering when the test ends
const _lineStep = 0.0045;

/// One bus line, along a street of [_lineStops] stops.
final _lineCatalog = <String, Object?>{
  'routes': [
    {
      'id': 'r1',
      'short': '1',
      'long': '${_lineStop(0)} - ${_lineStop(_lineStops - 1)}',
      'type': 'bus',
    },
  ],
  'stops': [
    for (var i = 0; i < _lineStops; i++)
      {
        'id': 's$i',
        'name': _lineStop(i),
        'code': '$i',
        'lat': _lineStopAt(i).latitude,
        'lon': _lineStopAt(i).longitude,
        'routes': [0],
      },
  ],
};

final _lineShapes = <String, Object?>{
  'routes': [
    {
      'lines': [
        {
          'dir': 0,
          'pts': [
            for (var i = 0; i < _lineStops; i++)
              [_lineStopAt(i).latitude, _lineStopAt(i).longitude],
          ],
          'stops': [for (var i = 0; i < _lineStops; i++) i],
        },
      ],
    },
  ],
};

/// Where [_plan]'s ride gets off: a stop short of the line's end, so the
/// option lies a little west of the map's first view, at about its zoom.
/// Framing it then renders no new tiles, which would still be rendering when
/// the test ends
const _alighting = _lineStops - 2;

/// About 7 m of longitude here, against the option's 3.3 km
const _sameDeg = 1e-4;

/// Two places to plan between, by the line's first stop and [_alighting]
final _ends = [
  Place(name: 'Home', at: _lineStopAt(0)),
  Place(name: 'Work', at: _lineStopAt(_alighting)),
];

/// One option, riding the line to [_alighting], 12 minutes door to door
final _plan = <String, Object?>{
  't': 0,
  'report': 'r1',
  'options': [
    {
      'dep': 0,
      'arr': 720,
      'rides': 1,
      'live': true,
      'confidence': 'live',
      'legs': [
        {'kind': 'walk', 'dep': 0, 'arr': 60, 'a': -1, 'b': 0},
        {
          'kind': 'ride',
          'dep': 60,
          'arr': 660,
          'a': 0,
          'b': _alighting,
          'route': 0,
          'live': true,
          'confidence': 'live',
        },
        {'kind': 'walk', 'dep': 660, 'arr': 720, 'a': _alighting, 'b': -1},
      ],
    },
  ],
};

/// The length of [_plan]'s option, as its summary reads in the language set
Finder get _optionLength => find.text(txt.minutes(12));
