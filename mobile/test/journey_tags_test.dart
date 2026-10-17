import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:commuterlviv/src/eta.dart';
import 'package:commuterlviv/src/journey_tags.dart';
import 'package:commuterlviv/src/models.dart';

// on a minute, so a few seconds later is still the same one on the clock
const t0 = 1790000040;
const minS = 60;
const door = LatLng(49.84, 24.0);
const stop = LatLng(49.841, 24.0);
const other = LatLng(49.85, 24.0);

Leg walk(int dep, int arr, [LatLng from = door, LatLng to = stop]) =>
    Leg(kind: 'walk', dep: dep, arr: arr, a: -1, b: 1, pts: [from, to]);

Leg ride(int dep, int arr, [LatLng from = stop, LatLng to = other]) => Leg(
  kind: 'ride',
  dep: dep,
  arr: arr,
  a: 1,
  b: 2,
  route: 7,
  pts: [from, to],
);

List<String> texts(List<Leg> legs) => [
  for (final tag in journeyTags(legs)) tag.text,
];

void main() {
  test('somebody already at the stop is shown only when the ride leaves', () {
    final legs = [walk(t0, t0 + 5, stop, stop), ride(t0 + 34, t0 + 10 * minS)];

    expect(texts(legs), [clockTime(t0 + 34), clockTime(t0 + 10 * minS)]);
  });

  test('a walk to the stop of a minute or more has its own times', () {
    final legs = [
      walk(t0, t0 + shortWalkS),
      ride(t0 + 2 * minS, t0 + 10 * minS),
    ];

    expect(texts(legs), [
      clockTime(t0),
      '${clockTime(t0 + shortWalkS)} → ${clockTime(t0 + 2 * minS)}',
      clockTime(t0 + 10 * minS),
    ]);
  });

  test('getting off and on again within a minute reads as one time', () {
    final legs = [
      ride(t0, t0 + 5, other, stop),
      ride(t0 + 30, t0 + 10 * minS, stop, other),
    ];

    expect(texts(legs)[1], clockTime(t0 + 30));
  });

  test('a short walk between two stops leaves each its own ride\'s time', () {
    final near = LatLng(stop.latitude, stop.longitude + 0.001);
    final legs = [
      ride(t0, t0 + 5 * minS, other, stop),
      walk(t0 + 5 * minS, t0 + 5 * minS + 40, stop, near),
      ride(t0 + 8 * minS, t0 + 20 * minS, near, door),
    ];

    expect(texts(legs), [
      clockTime(t0),
      clockTime(t0 + 5 * minS),
      clockTime(t0 + 8 * minS),
      clockTime(t0 + 20 * minS),
    ]);
  });

  test(
    'two stops 25 m apart or more keep a pill each, whichever way they lie',
    () {
      // 20 m north and 20 m east: each closer than 25 m, the two together 28 m
      final corner = LatLng(stop.latitude + 0.00018, stop.longitude + 0.00028);
      final legs = [
        ride(t0, t0 + 5 * minS, other, stop),
        ride(t0 + 5 * minS + 30, t0 + 20 * minS, corner, door),
      ];

      expect(texts(legs), [
        clockTime(t0),
        clockTime(t0 + 5 * minS),
        clockTime(t0 + 5 * minS + 30),
        clockTime(t0 + 20 * minS),
      ]);
    },
  );
}
