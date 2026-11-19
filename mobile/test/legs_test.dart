import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

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

  test('the vehicles ridden are those the rides are planned on', () {
    final j = journey(0, 0);
    final legs = [...j.legs];
    final r = legs[1];
    legs[1] = Leg(
      kind: r.kind,
      dep: r.dep,
      arr: r.arr,
      a: r.a,
      b: r.b,
      route: r.route,
      veh: 412,
    );
    final planned = Journey(
      dep: j.dep,
      arr: j.arr,
      rides: j.rides,
      live: j.live,
      confidence: j.confidence,
      legs: legs,
    );

    expect(riddenBy(planned), {412});
    expect(riddenBy(null), isEmpty);
  });

  group('underWay', () {
    // A walk north along a meridian, a point every ~111 m
    const step = 0.001;
    final pts = [for (var i = 0; i < 5; i++) LatLng(49.8 + i * step, 24.0)];
    Journey walking() {
      final j = journey(0, 0);
      final w = j.legs[0];
      return Journey(
        dep: j.dep,
        arr: j.arr,
        rides: j.rides,
        live: j.live,
        confidence: j.confidence,
        legs: [
          Leg(kind: w.kind, dep: w.dep, arr: w.arr, a: w.a, b: w.b, pts: pts),
          ...j.legs.skip(1),
        ],
      );
    }

    Progress at(Stage stage, double left, {bool astray = false}) => Progress(
      stage: stage,
      left: left,
      astray: astray,
      passed: false,
      soon: false,
    );
    const here = LatLng(49.8015, 24.0002);
    const now = t0 + minS;

    test('draws the walk under way from where I am, along what is left', () {
      final j = underWay(
        walking(),
        at(const Stage(StageKind.walk, 0), 250),
        here,
        now,
      );

      expect(j.legs[0].pts, [here, ...pts.skip(2)]);
      expect(j.legs[0].dep, now);
    });

    test('leaves a walk strayed from as planned', () {
      final plan = walking();

      final j = underWay(
        plan,
        at(const Stage(StageKind.walk, 0), 250, astray: true),
        here,
        now,
      );

      expect(j.legs, plan.legs);
    });

    test('leaves the legs already done off, once waiting or aboard', () {
      final plan = walking();

      for (final stage in const [
        Stage(StageKind.wait, 1),
        Stage(StageKind.ride, 1, 7),
      ]) {
        expect(underWay(plan, at(stage, 0), here, now).legs, plan.legs.skip(1));
      }
    });

    test('leaves an arrived journey whole', () {
      final plan = walking();

      expect(
        underWay(plan, at(const Stage(StageKind.arrived), 0), here, now),
        same(plan),
      );
    });
  });

  group('liveRows', () {
    /// A walk north along a meridian, a point every ~111 m
    const step = 0.001;
    Journey walking() {
      final j = journey(3 * minS, 0);
      return Journey(
        dep: j.dep,
        arr: j.arr,
        rides: j.rides,
        live: j.live,
        confidence: j.confidence,
        legs: [
          Leg(
            kind: 'walk',
            dep: j.legs[0].dep,
            arr: j.legs[0].arr,
            a: j.legs[0].a,
            b: j.legs[0].b,
            pts: [for (var i = 0; i < 5; i++) LatLng(49.8 + i * step, 24.0)],
          ),
          ...j.legs.skip(1),
        ],
      );
    }

    Arrival arrival(int route, int veh, int t) =>
        Arrival(route: route, veh: veh, t: t);

    test('the walk under way ends when the metres left take it', () {
      final j = walking();
      final at = t0 + 4 * minS;
      final got = liveRows(
        j,
        LivePlan(
          now: at,
          stage: const Stage(StageKind.walk, 0),
          left: 222,
          arrivals: const {},
        ),
      );

      // Half the ~445 m line left at the pace it was planned at: half of 5 min
      expect(got[0].kind, PlanRowKind.walk);
      expect(got[0].arr, closeTo(at + 150, 1));
    });

    test("a ride's arrival and the walk after it follow its prediction", () {
      final got = liveRows(
        journey(3 * minS, 0),
        LivePlan(
          now: t0 + 6 * minS,
          stage: const Stage(StageKind.ride, 1, 42),
          left: 0,
          arrivals: {
            1: [arrival(7, 42, t0 + 5 * minS)],
            2: [arrival(7, 42, t0 + 20 * minS)],
          },
        ),
      );

      expect(
        got.firstWhere((r) => r.kind == PlanRowKind.ride && r.leg == 1).arr,
        t0 + 20 * minS,
      );
      final after = got.firstWhere(
        (r) => r.kind == PlanRowKind.walk && r.leg == 2,
      );
      expect((after.dep, after.arr), (t0 + 20 * minS, t0 + 22 * minS));
      expect(got.last.arr, t0 + 37 * minS);
    });

    test('a ride waited for takes its times from the prediction', () {
      final got = liveRows(
        journey(3 * minS, 0),
        LivePlan(
          now: t0 + 9 * minS,
          stage: const Stage(StageKind.wait, 1),
          left: 0,
          arrivals: {
            1: [arrival(7, 42, t0 + 12 * minS)],
            2: [arrival(7, 42, t0 + 22 * minS)],
          },
        ),
      );

      final wait = got.firstWhere(
        (r) => r.kind == PlanRowKind.wait && r.leg == 1,
      );
      expect((wait.dep, wait.arr), (t0 + 5 * minS, t0 + 12 * minS));
      final rideRow = got.firstWhere(
        (r) => r.kind == PlanRowKind.ride && r.leg == 1,
      );
      expect((rideRow.dep, rideRow.arr), (t0 + 12 * minS, t0 + 22 * minS));
      expect(got.last.arr, t0 + 39 * minS);
    });

    test('a waited ride takes the bus that leaves first, not its next lap', () {
      final j = journey(3 * minS, 0);
      j.legs[1] = Leg(
        kind: 'ride',
        dep: j.legs[1].dep,
        arr: j.legs[1].arr,
        a: 1,
        b: 2,
        route: 7,
        veh: 42,
      );
      final got = liveRows(
        j,
        LivePlan(
          now: t0 + 10 * minS,
          stage: const Stage(StageKind.wait, 1),
          left: 0,
          arrivals: {
            1: [
              Arrival(route: 7, veh: 42, t: t0 + 15 * minS, planned: true),
              arrival(7, 8, t0 + 12 * minS),
            ],
            2: [arrival(7, 42, t0 + 14 * minS), arrival(7, 8, t0 + 22 * minS)],
          },
        ),
      );

      final rideRow = got.firstWhere(
        (r) => r.kind == PlanRowKind.ride && r.leg == 1,
      );
      expect((rideRow.dep, rideRow.arr), (t0 + 12 * minS, t0 + 22 * minS));
    });

    test(
      "the alight arrival is the chosen trip's, not the vehicle's earlier",
      () {
        final j = journey(0, 0);
        j.legs[1] = Leg(
          kind: 'ride',
          dep: j.legs[1].dep,
          arr: j.legs[1].arr,
          a: 1,
          b: 2,
          route: 7,
          veh: 42,
        );
        final got = liveRows(
          j,
          LivePlan(
            now: t0 + 4 * minS,
            stage: const Stage(StageKind.walk, 0),
            left: 0,
            arrivals: {
              1: [arrival(7, 42, t0 + 5 * minS)],
              2: [
                arrival(7, 42, t0 + 6 * minS),
                arrival(7, 42, t0 + 20 * minS),
                arrival(7, 8, t0 + 14 * minS),
              ],
            },
          ),
        );

        final rideRow = got.firstWhere(
          (r) => r.kind == PlanRowKind.ride && r.leg == 1,
        );
        expect((rideRow.dep, rideRow.arr), (t0 + 5 * minS, t0 + 6 * minS));
      },
    );

    test(
      "a vehicle five seconds before the walk ends is shown at the walk's end",
      () {
        final j = journey(0, 0);
        j.legs[1] = Leg(
          kind: 'ride',
          dep: j.legs[1].dep,
          arr: j.legs[1].arr,
          a: 1,
          b: 2,
          route: 7,
          veh: 42,
        );
        final got = liveRows(
          j,
          LivePlan(
            now: t0 + 4 * minS,
            stage: const Stage(StageKind.walk, 0),
            left: 0,
            arrivals: {
              1: [arrival(7, 42, t0 + 4 * minS - 5)],
              2: [arrival(7, 42, t0 + 14 * minS)],
            },
          ),
        );

        final rideRow = got.firstWhere(
          (r) => r.kind == PlanRowKind.ride && r.leg == 1,
        );
        expect((rideRow.dep, rideRow.arr), (t0 + 4 * minS, t0 + 14 * minS));
      },
    );

    test("a planned vehicle that is gone is replaced by the route's next", () {
      final got = liveRows(
        journey(0, 0),
        LivePlan(
          now: t0 + 4 * minS,
          stage: const Stage(StageKind.walk, 0),
          left: 0,
          arrivals: {
            1: [arrival(7, 8, t0 + 8 * minS)],
            2: [arrival(7, 8, t0 + 18 * minS)],
          },
        ),
      );

      final rideRow = got.firstWhere(
        (r) => r.kind == PlanRowKind.ride && r.leg == 1,
      );
      expect((rideRow.dep, rideRow.arr), (t0 + 8 * minS, t0 + 18 * minS));
    });
  });

  group('betterPlan', () {
    Journey option(int arr) => Journey(
      dep: t0,
      arr: arr,
      rides: 2,
      live: true,
      confidence: Confidence.live,
      legs: journey(0, 0).legs,
    );

    test('keeps a plan that still works unless another is clearly sooner', () {
      expect(betterPlan(1000, [option(1000 - betterS + 1)], false), isNull);
      expect(
        betterPlan(1000, [option(1000 - betterS)], false)?.arr,
        1000 - betterS,
      );
    });

    test('takes the best there is when the plan is broken', () {
      expect(betterPlan(1000, [option(5000)], true)?.arr, 5000);
      expect(betterPlan(1000, const [], true), isNull);
    });
  });

  test('samePlan is the same legs with the same times', () {
    expect(samePlan(journey(0, 0), journey(0, 0)), isTrue);
    expect(samePlan(journey(0, 0), journey(1, 0)), isFalse);
  });
}
