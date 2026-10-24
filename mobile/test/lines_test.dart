import 'package:commuterlviv/src/lines.dart';
import 'package:commuterlviv/src/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

RouteLine _line(int dir, List<int> stops) =>
    RouteLine(dir: dir, pts: const [], stops: stops);

Arrival _at(int route, int veh, int t, {bool planned = false}) =>
    Arrival(route: route, veh: veh, t: t, planned: planned);

void main() {
  group('directions', () {
    test('lists each way once, by the shape calling at the most stops', () {
      final shape = RouteShape(
        lines: [
          _line(1, [3, 2, 1, 0]),
          _line(0, [0, 1]),
          _line(0, [0, 1, 2, 3]),
        ],
        twoWay: true,
      );

      expect(
        [for (final d in directions(shape)) d.stops],
        [
          [0, 1, 2, 3],
          [3, 2, 1, 0],
        ],
      );
      expect([for (final d in directions(shape)) d.dir], [0, 1]);
    });

    test('has nothing to list from a service that sends no stops', () {
      final shape = RouteShape(lines: [_line(0, const [])], twoWay: false);

      expect(directions(shape), isEmpty);
      expect(directions(null), isEmpty);
    });

    test('reads the stops of a line from the wire, and none where absent', () {
      final sent = RouteLine.fromJson({
        'dir': 0,
        'pts': [
          [49.8, 24.0],
        ],
        'stops': [4, 2],
      });
      final old = RouteLine.fromJson({'dir': 0, 'pts': <Object>[]});

      expect(sent.stops, [4, 2]);
      expect(old.stops, isEmpty);
    });
  });

  group('lineRows', () {
    test("gives each stop this route's next arrival, not another route's", () {
      final rows = lineRows(
        [5, 6],
        {
          5: [_at(9, 1, 50), _at(2, 3, 80)],
        },
        2,
      );

      expect([for (final r in rows) r.next?.t], [80, null]);
    });

    test('puts a vehicle at the stop it reaches soonest', () {
      final rows = lineRows(
        [0, 1, 2],
        {
          0: [_at(2, 7, 300)],
          1: [_at(2, 4, 100)],
          2: [_at(2, 4, 200), _at(2, 7, 400)],
        },
        2,
      );

      expect(
        [for (final r in rows) r.vehs],
        [
          [7],
          [4],
          <int>[],
        ],
      );
    });

    test('leaves a vehicle finishing its previous trip off the line', () {
      final rows = lineRows(
        [0],
        {
          0: [_at(2, 7, 300, planned: true)],
        },
        2,
      );

      expect(rows.single.vehs, isEmpty);
      expect(rows.single.next?.veh, 7);
    });
  });

  test('routesNear takes the routes of the stops within the radius only', () {
    const catalog = Catalog(
      routes: [],
      stops: [
        Stop(
          id: 'a',
          name: 'A',
          code: '',
          lat: 49.84,
          lon: 24.03,
          routes: [0, 1],
        ),
        Stop(id: 'b', name: 'B', code: '', lat: 49.85, lon: 24.03, routes: [2]),
      ],
      index: {},
      stopIndex: {},
    );

    expect(routesNear(catalog, const LatLng(49.8405, 24.03), 500), {0, 1});
  });

  group('opened', () {
    test('puts the line opened first, once', () {
      expect(opened(['a', 'b', 'c'], 'b'), ['b', 'a', 'c']);
    });

    test('keeps only the latest few', () {
      final many = [for (var i = 0; i < recentLines; i++) 'r$i'];

      expect(opened(many, 'new'), ['new', ...many.take(recentLines - 1)]);
    });
  });
}
