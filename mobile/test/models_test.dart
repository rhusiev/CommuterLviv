import 'package:flutter_test/flutter_test.dart';

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
}
