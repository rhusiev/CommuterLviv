import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/here.dart';
import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/route_badge.dart';
import 'package:commuterlviv/src/searched.dart';
import 'package:commuterlviv/src/stop_search.dart';
import 'package:commuterlviv/src/strings.dart';

const _catalog = Catalog(
  routes: [
    TransitRoute(
      id: 'r0',
      short: 'Тр25',
      long: 'Market - Depot',
      type: 'trolleybus',
    ),
  ],
  stops: [
    Stop(
      id: 's0',
      name: 'Market',
      code: '100',
      lat: 49.84,
      lon: 24.03,
      routes: [0],
    ),
    Stop(
      id: 's1',
      name: 'Depot',
      code: '101',
      lat: 49.841,
      lon: 24.03,
      routes: [],
    ),
    Stop(
      id: 's2',
      name: 'Airport',
      code: '102',
      lat: 49.82,
      lon: 23.96,
      routes: [],
    ),
  ],
  index: {},
  stopIndex: {'s0': 0, 's1': 1, 's2': 2},
);

const _home = Place(name: 'Market home', at: LatLng(49.85, 24.04));
const _work = Place(name: 'Work', at: LatLng(49.83, 24.02));

/// Past the debounce, so the service has been asked and has failed: tests get
/// no network
const _settled = Duration(seconds: 1);

/// About 22 m north of Depot and 111 m more of Market, the first in the
/// catalog; Airport is 5.5 km off
const _me = LatLng(49.8412, 24.03);

/// Locates at [at] when started, or is refused with none
class _Here extends Here {
  _Here(this.at) : super(onFirstFix: (_) {});

  final LatLng? at;
  int started = 0;

  @override
  Future<LatLng?> start() async {
    started++;
    final at = this.at;
    if (at == null) {
      state = Locating.denied;
    } else {
      fix = Fix(at, 5, 0);
      state = Locating.on;
    }
    notifyListeners();
    return at;
  }
}

/// A service whose place search finds nothing
class _NoPlaces implements Api {
  @override
  List<Searched> get searched => const [];

  @override
  Future<List<Found>> find(String q) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Opens the search over [places]; the hit it closes with lands in [picked]
Future<void> open(
  WidgetTester tester,
  void Function(Hit?) picked, {
  Here? here,
  Api? service,
  LatLng? around,
}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final api = service ?? await Api.open();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => picked(
            await showSearch<Hit?>(
              context: context,
              delegate: StopSearch(
                api: api,
                catalog: _catalog,
                places: const [_work, _home],
                onSave: (_, _) {},
                here: here,
                around: around,
              ),
            ),
          ),
          child: const Text('search'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('search'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the clear and back buttons say what they do', (tester) async {
    Hit? picked;
    await open(tester, (hit) => picked = hit);
    await tester.enterText(find.byType(TextField), 'mark');
    await tester.pump(_settled);

    await tester.tap(find.byTooltip(txt.clear));
    await tester.pump();
    expect(find.text('mark'), findsNothing);
    expect(find.byTooltip(txt.clear), findsNothing);

    final back = MaterialLocalizations.of(
      tester.element(find.byType(TextField)),
    ).backButtonTooltip;
    await tester.tap(find.byTooltip(back));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(picked, isNull);
  });

  testWidgets('a saved place the query matches comes first, and is picked as '
      'a place', (tester) async {
    Hit? picked;
    await open(tester, (hit) => picked = hit);

    await tester.enterText(find.byType(TextField), 'mark');
    await tester.pump(_settled);

    expect(find.text(_work.name), findsNothing);
    final order = [txt.places, _home.name, txt.foundStops, 'Market'];
    final tops = [for (final t in order) tester.getTopLeft(find.text(t)).dy];
    expect(tops, orderedEquals([...tops]..sort()));
    await tester.tap(find.text(_home.name));
    await tester.pumpAndSettle();
    expect(picked, isA<PlaceHit>().having((p) => p.at, 'at', _home.at));
  });

  testWidgets('a stop picked is offered again first before anything is typed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final api = await Api.open();
    await open(tester, (_) {}, service: api);
    expect(find.text(txt.recentSearches), findsNothing);
    await tester.enterText(find.byType(TextField), 'mark');
    await tester.pump(_settled);
    await tester.tap(find.text('Market'));
    await tester.pumpAndSettle();

    await open(tester, (_) {}, service: api);

    expect(find.text(txt.recentSearches), findsOneWidget);
    expect(find.text('Market'), findsOneWidget);
  });

  testWidgets('a stop found names its routes by their badges, not by the '
      "feed's names", (tester) async {
    await open(tester, (_) {});

    await tester.enterText(find.byType(TextField), 'mark');
    await tester.pump(_settled);

    expect(find.byType(RouteBadge), findsOneWidget);
    expect(find.text('25'), findsOneWidget);
    expect(find.textContaining('Тр25'), findsNothing);
  });

  testWidgets('a query nothing matches says so once places have been looked '
      'for', (tester) async {
    await open(tester, (_) {}, service: _NoPlaces());

    await tester.enterText(find.byType(TextField), 'nowhere');
    await tester.pump();
    expect(find.text(txt.nothingFound), findsNothing);
    await tester.pump(_settled);

    expect(find.text(txt.nothingFound), findsOneWidget);
  });

  test('the stops near a point are those within reach, nearest first', () {
    expect(nearest(_catalog, _me).map((n) => n.$1), [1, 0]);
  });

  test('only so many of the stops near a point are listed', () {
    final crowded = Catalog(
      routes: const [],
      stops: [
        for (var i = 0; i <= nearCount; i++)
          Stop(
            id: 's$i',
            name: '$i',
            code: '$i',
            lat: _me.latitude,
            lon: _me.longitude,
            routes: const [],
          ),
      ],
      index: const {},
      stopIndex: const {},
    );

    expect(nearest(crowded, _me), hasLength(nearCount));
  });

  testWidgets('with nothing typed, the stops near the phone are offered once '
      'asked for, and one is picked as a stop', (tester) async {
    Hit? picked;
    final here = _Here(_me);
    await open(tester, (hit) => picked = hit, here: here);

    expect(here.started, 0);
    expect(find.text('Depot'), findsNothing);
    await tester.tap(find.text(txt.nearMe));
    await tester.pumpAndSettle();

    expect(here.started, 1);
    expect(find.text('Airport'), findsNothing);
    expect(find.text(txt.metres(22)), findsOneWidget);
    final depot = tester.getTopLeft(find.text('Depot')).dy;
    expect(tester.getTopLeft(find.text('Market')).dy, greaterThan(depot));
    await tester.tap(find.text('Market'));
    await tester.pumpAndSettle();
    expect(picked, isA<StopHit>().having((h) => h.stop, 'stop', 0));
  });

  testWidgets('a refusal says how to allow it', (tester) async {
    await open(tester, (_) {}, here: _Here(null));

    await tester.tap(find.text(txt.nearMe));
    await tester.pumpAndSettle();

    expect(find.text(txt.noLocation), findsOneWidget);
  });

  testWidgets('a phone far from every stop is told so', (tester) async {
    await open(tester, (_) {}, here: _Here(const LatLng(50.45, 30.52)));

    await tester.tap(find.text(txt.nearMe));
    await tester.pumpAndSettle();

    expect(find.text(txt.nothingNear), findsOneWidget);
  });

  testWidgets('a point held on the map lists the stops near it, nearest '
      'first, without asking where the phone is', (tester) async {
    final here = _Here(null);
    await open(tester, (_) {}, here: here, around: _me);

    expect(here.started, 0);
    expect(find.text(txt.nearHere), findsOneWidget);
    expect(find.text(txt.metres(22)), findsOneWidget);
    expect(find.text('Airport'), findsNothing);
    final depot = tester.getTopLeft(find.text('Depot')).dy;
    expect(tester.getTopLeft(find.text('Market')).dy, greaterThan(depot));
  });

  testWidgets('a point held far from every stop is told so', (tester) async {
    await open(tester, (_) {}, around: const LatLng(50.45, 30.52));

    expect(find.text(txt.nothingNearHere), findsOneWidget);
  });
}
