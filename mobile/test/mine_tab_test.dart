import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/due.dart';
import 'package:commuterlviv/src/live.dart';
import 'package:commuterlviv/src/mine_tab.dart';
import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/strings.dart';

final _catalog = Catalog(
  routes: const [
    TransitRoute(id: 'r48', short: '48', long: 'A to B', type: 'bus'),
  ],
  stops: const [
    Stop(
      id: 's1',
      name: 'Opera',
      code: '1',
      lat: 49.84,
      lon: 24.03,
      routes: [0],
    ),
  ],
  index: const {'r48': 0},
  stopIndex: const {'s1': 0},
);

const _home = Place(name: 'Home', at: LatLng(49.8, 24.0));
const _work = Place(name: 'Work', at: LatLng(49.9, 24.1));
const _set = RouteSet(id: 'x', name: 'Commute', routes: ['r48'], ord: 0);

/// What the tab reported back, one field per callback.
class _Heard {
  List<int>? pins;
  List<Place>? places;
  Place? place;
  int? stop;
  RouteSet? activated;
  (RouteSet, String)? renamed;
  RouteSet? deleted;
  bool account = false;
}

Future<_Heard> _pump(
  WidgetTester tester, {
  List<int> pins = const [],
  List<Place> places = const [],
  List<RouteSet> sets = const [],
  Map<int, List<Arrival>> arrivals = const {},
}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final live = Live(await Api.open(), onRenewed: () {})..arrivals = arrivals;
  final heard = _Heard();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MineTab(
          catalog: _catalog,
          live: live,
          pins: pins,
          onPins: (next) => heard.pins = next,
          onStop: (stop) => heard.stop = stop,
          watching: const {},
          onWatch: (_) {},
          onLine: (_) {},
          places: places,
          onPlaces: (next) => heard.places = next,
          onPlace: (place) => heard.place = place,
          sets: Sets(sets: sets, active: null, pins: const [], places: places),
          onActivate: (set) => heard.activated = set,
          onRename: (set, name) async => heard.renamed = (set, name),
          onDelete: (set) async => heard.deleted = set,
          username: 'tester',
          onAccount: () => heard.account = true,
        ),
      ),
    ),
  );
  return heard;
}

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dy;

void main() {
  testWidgets('pins, places and sets come in that order, the account last', (
    tester,
  ) async {
    final heard = await _pump(
      tester,
      pins: const [0],
      places: const [_home],
      sets: const [_set],
    );

    final order = [
      txt.pinnedStops,
      'Opera',
      txt.places,
      'Home',
      txt.sets,
      'Commute',
      txt.account,
    ].map((text) => _top(tester, text)).toList();
    expect(order, [...order]..sort());
    expect(find.text('tester'), findsOneWidget);

    await tester.tap(find.text(txt.account));
    expect(heard.account, isTrue);
  });

  testWidgets('a pinned stop shows what is due and unpins', (tester) async {
    final soon = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 300;
    final heard = await _pump(
      tester,
      pins: const [0],
      arrivals: {
        0: [Arrival(route: 0, veh: 7, t: soon)],
      },
    );

    expect(find.text('Opera'), findsOneWidget);
    expect(find.text('48'), findsOneWidget);
    await tester.tap(find.text('Opera'));
    expect(heard.stop, 0);

    await tester.tap(find.byTooltip(txt.unpin));
    expect(heard.pins, isEmpty);
  });

  testWidgets('a pinned stop flows its due chips from under its name', (
    tester,
  ) async {
    final soon = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 300;
    await _pump(
      tester,
      pins: const [0],
      arrivals: {
        0: [
          Arrival(route: 0, veh: 7, t: soon),
          Arrival(route: 0, veh: 8, t: soon + 300),
        ],
      },
    );

    final chips = find.byType(Due);
    final first = tester.getTopLeft(chips.at(0));
    final second = tester.getTopLeft(chips.at(1));
    expect(first.dx, tester.getTopLeft(find.text('Opera')).dx);
    expect(second.dy, first.dy);
    expect(second.dx, greaterThan(first.dx));
  });

  testWidgets('a rename rewrites the whole list, in order', (tester) async {
    final heard = await _pump(tester, places: const [_home, _work]);

    await tester.longPress(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(txt.rename));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Flat');
    await tester.tap(find.text(txt.save));
    await tester.pumpAndSettle();

    expect([for (final p in heard.places!) p.name], ['Flat', 'Work']);
    expect(heard.places!.first.at, _home.at);
  });

  testWidgets('a tap shows the place', (tester) async {
    final heard = await _pump(tester, places: const [_home]);

    await tester.tap(find.text('Home'));

    expect((heard.place?.name, heard.place?.at), ('Home', _home.at));
  });

  testWidgets('a set activates on a tap and renames on a hold', (tester) async {
    final heard = await _pump(tester, sets: const [_set]);

    await tester.tap(find.text('Commute'));
    expect(heard.activated?.id, 'x');

    await tester.longPress(find.text('Commute'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(txt.rename));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Work run');
    await tester.tap(find.text(txt.save));
    await tester.pumpAndSettle();

    expect((heard.renamed?.$1.id, heard.renamed?.$2), ('x', 'Work run'));
  });

  testWidgets('each empty section says how it fills', (tester) async {
    await _pump(tester);

    expect(find.text(txt.pinAStop), findsOneWidget);
    expect(find.text(txt.saveHow), findsOneWidget);
    expect(find.text(txt.noSets), findsOneWidget);
    expect(find.text(txt.holdToManage), findsNothing);
    expect(find.text(txt.account), findsOneWidget);
  });
}
