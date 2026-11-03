import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:commuterlviv/src/searched.dart';

const _park = Searched.place('Park', LatLng(49.82, 24.02));

void main() {
  test(
    'the latest pick comes first, a pick again moved up, not listed twice',
    () {
      var held = <Searched>[];
      for (final s in [
        const Searched.stop('s1'),
        _park,
        const Searched.stop('s1'),
      ]) {
        held = withPicked(held, s);
      }

      expect([for (final s in held) s.stop ?? s.name], ['s1', 'Park']);
    },
  );

  test('only the last few are kept', () {
    var held = <Searched>[];
    for (var i = 0; i < searchedKept + 2; i++) {
      held = withPicked(held, Searched.stop('s$i'));
    }

    expect([for (final s in held) s.stop], ['s4', 's3', 's2']);
  });

  test('a pick reads back as it was kept, and junk reads as nothing', () {
    final back = Searched.fromJson(_park.toJson())!;

    expect((back.name, back.at), ('Park', _park.at));
    expect(Searched.fromJson('{not json'), isNull);
  });
}
