import 'package:flutter_test/flutter_test.dart';

import 'package:commuterlviv/src/follow.dart';
import 'package:commuterlviv/src/legs.dart';
import 'package:commuterlviv/src/models.dart';

const t0 = 1790000000;
const minS = 60;

Leg walk(int dep, int arr, int a, int b) =>
    Leg(kind: 'walk', dep: dep, arr: arr, a: a, b: b);

Leg ride(int dep, int arr, int a, int b, [int route = 7]) =>
    Leg(kind: 'ride', dep: dep, arr: arr, a: a, b: b, route: route);

/// Door to stop 1, route 7 to stop 2, change on foot to stop 3, route 9 to
/// stop 4, walk to the door - [waits] seconds at stop 1 and [change] at 3
Journey journey(int waits, int change, {bool aboard = false}) {
  final r1 = t0 + 5 * minS + waits;
  final w2 = r1 + 10 * minS;
  final r2 = w2 + 2 * minS + change;
  final legs = [
    walk(t0, t0 + 5 * minS, -1, 1),
    ride(r1, w2, 1, 2),
    walk(w2, w2 + 2 * minS, 2, 3),
    ride(r2, r2 + 10 * minS, 3, 4, 9),
    walk(r2 + 10 * minS, r2 + 15 * minS, 4, -1),
  ];
  return Journey(
    dep: t0,
    arr: r2 + 15 * minS,
    rides: 2,
    live: true,
    confidence: Confidence.live,
    legs: aboard ? legs.sublist(1) : legs,
    aboard: aboard,
  );
}

void main() {
  test('lists each leg with a wait before a ride a minute or more later', () {
    final j = journey(3 * minS, waitMinS);

    final got = rows(j);

    expect(
      [for (final r in got) (r.kind, r.leg)],
      [
        (PlanRowKind.walk, 0),
        (PlanRowKind.wait, 1),
        (PlanRowKind.ride, 1),
        (PlanRowKind.walk, 2),
        (PlanRowKind.wait, 3),
        (PlanRowKind.ride, 3),
        (PlanRowKind.walk, 4),
      ],
    );
    expect(
      (got[1].dep, got[1].arr, got[1].a),
      (j.legs[0].arr, j.legs[1].dep, 1),
    );
    expect((got[5].route, got[5].a, got[5].b), (9, 3, 4));
  });

  test('a gap under a minute gets no wait', () {
    final got = rows(journey(waitMinS - 1, 0));
    expect(got.any((r) => r.kind == PlanRowKind.wait), isFalse);
  });

  test('only the walk between two rides is a change', () {
    final got = rows(journey(0, 0)).where((r) => r.kind == PlanRowKind.walk);
    expect(
      [for (final r in got) (r.b, r.change)],
      [(1, false), (3, true), (-1, false)],
    );
  });

  test('a journey begun on board has no wait before its first ride', () {
    final got = rows(journey(0, 0, aboard: true));
    expect((got[0].kind, got[0].leg), (PlanRowKind.ride, 0));
  });

  group('current', () {
    final list = rows(journey(3 * minS, 0));

    test('waiting is on the wait, riding on the ride', () {
      expect(
        list[current(list, const Stage(StageKind.wait, 1))].kind,
        PlanRowKind.wait,
      );
      expect(
        list[current(list, const Stage(StageKind.ride, 1))].kind,
        PlanRowKind.ride,
      );
    });

    test('waiting for a ride with no wait listed is on the ride', () {
      final row = list[current(list, const Stage(StageKind.wait, 3))];
      expect((row.kind, row.leg), (PlanRowKind.ride, 3));
    });

    test('arrived is on no row', () {
      expect(current(list, const Stage(StageKind.arrived)), -1);
    });
  });
}
