import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/point_label.dart';
import 'package:commuterlviv/src/strings.dart';

/// 1e-3 degrees of latitude is 111 m
const _catalog = Catalog(
  routes: [],
  stops: [
    Stop(
      id: 's0',
      name: 'Ринок (100)',
      code: '',
      lat: 49.842,
      lon: 24.03,
      routes: [],
    ),
    Stop(
      id: 's1',
      name: 'Підвальна',
      code: '',
      lat: 49.845,
      lon: 24.03,
      routes: [],
    ),
  ],
  index: {},
  stopIndex: {},
);

void main() {
  test('a point is named by the nearest stop, without its code', () {
    expect(
      pointLabel(_catalog, const LatLng(49.8431, 24.03)),
      txt.nearStop('Ринок'),
    );
    expect(
      pointLabel(_catalog, const LatLng(49.8441, 24.03)),
      txt.nearStop('Підвальна'),
    );
  });

  test('a point no stop is near gives its coordinates', () {
    expect(
      pointLabel(_catalog, const LatLng(49.836, 24.03)),
      '49.8360, 24.0300',
    );
  });

  test('a stop names a point as far as the web lets it, and no further', () {
    const degPerM = 1 / 111195;
    const edge = 49.842 - namesNearM * degPerM;
    expect(
      pointLabel(_catalog, const LatLng(edge + degPerM, 24.03)),
      txt.nearStop('Ринок'),
    );
    expect(
      pointLabel(_catalog, const LatLng(edge - degPerM, 24.03)),
      isNot(txt.nearStop('Ринок')),
    );
  });
}
