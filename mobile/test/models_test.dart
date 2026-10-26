import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:commuterlviv/src/models.dart';

const _catalog = Catalog(
  routes: [TransitRoute(id: 'r38', short: '38', long: 'A to B', type: 'tram')],
  stops: [
    Stop(id: 's0', name: 'Home stop', code: '0', lat: 0, lon: 0, routes: []),
  ],
  index: {'r38': 0},
  stopIndex: {'s0': 0},
);

void main() {
  test('a stop or route the catalog lacks is none, not an error', () {
    expect(_catalog.stopName(0), 'Home stop');
    expect(_catalog.stopName(-1), '');
    expect(_catalog.stopName(1), '');
    expect(_catalog.routeAt(0)?.short, '38');
    expect(_catalog.routeAt(-1), isNull);
    expect(_catalog.routeAt(1), isNull);
    expect(_catalog.routeAt(null), isNull);
  });

  test('a stop no route asked for calls at is faint, not left out', () {
    const catalog = Catalog(
      routes: [],
      stops: [
        Stop(id: 's0', name: 'A', code: '', lat: 0, lon: 0, routes: [0]),
        Stop(id: 's1', name: 'B', code: '', lat: 0, lon: 0, routes: [1]),
        Stop(id: 's2', name: 'C', code: '', lat: 0, lon: 0, routes: [0, 1]),
      ],
      index: {},
      stopIndex: {},
    );

    final (:stops, :faint) = catalog.splitStops({1});

    expect(stops, [1, 2]);
    expect(faint, [0]);
  });

  test("a journey's extent is its legs' points and the stops they meet, not "
      'the door or a stop the catalog lacks', () {
    const walk = [LatLng(1, 1), LatLng(2, 2)];
    const journey = Journey(
      dep: 0,
      arr: 0,
      rides: 1,
      live: false,
      confidence: Confidence.live,
      legs: [
        Leg(kind: 'walk', dep: 0, arr: 0, a: -1, b: 0, pts: walk),
        Leg(kind: 'ride', dep: 0, arr: 0, a: 0, b: 1),
      ],
    );

    // The walk and the ride both meet the stop
    expect(journey.extent(_catalog), [
      ...walk,
      const LatLng(0, 0),
      const LatLng(0, 0),
    ]);
  });

  test('a password may be changed only where the service says so', () {
    Me me(Map<String, dynamic> extra) => Me.fromJson({
      'username': 'u',
      'sets': {'sets': <Object>[], 'active': null},
      ...extra,
    });

    expect(me({'password_change': true}).passwordChange, isTrue);
    expect(me({'password_change': false}).passwordChange, isFalse);
    expect(me({}).passwordChange, isFalse);
  });

  test('a place is at a point a few metres off, not one a street away', () {
    const home = Place(name: 'Home', at: LatLng(49.84, 24.03));

    expect(home.isAt(const LatLng(49.84005, 24.02995)), isTrue);
    expect(home.isAt(const LatLng(49.841, 24.03)), isFalse);
  });

  group('a stop title', () {
    ({String name, String code}) titled(String name, String code) => Stop(
      id: 's',
      name: name,
      code: code,
      lat: 0,
      lon: 0,
      routes: const [],
    ).title;

    test('says a code the name repeats once, as the name says it', () {
      expect(titled('ТРЦ Кінг Кросс (320)', '0320'), (
        name: 'ТРЦ Кінг Кросс',
        code: '320',
      ));
      expect(titled('Площа Франка (311)', '0280'), (
        name: 'Площа Франка',
        code: '311',
      ));
    });

    test('moves a code only in the name out of it', () {
      expect(titled('Кордуби (265)', ''), (name: 'Кордуби', code: '265'));
      expect(titled('ТРЦ Кінг Кросс (320-01)', ''), (
        name: 'ТРЦ Кінг Кросс',
        code: '320-01',
      ));
    });

    test('leaves a name without a code, or with words in brackets, and '
        'unpads the code', () {
      expect(titled('ПЛ. СОБОРНА', '0074-01'), (
        name: 'ПЛ. СОБОРНА',
        code: '74-01',
      ));
      expect(titled('Ринок', '0'), (name: 'Ринок', code: '0'));
      expect(titled('Ринок (на вимогу)', ''), (
        name: 'Ринок (на вимогу)',
        code: '',
      ));
    });
  });
}
