import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:commuterlviv/src/follow.dart';
import 'package:commuterlviv/src/models.dart';

const lat0 = 49.84;
const lon0 = 24.03;
const route = 7;
const planned = 41;
const fixEveryMs = 2000;
const mPerDegree = 6371000 * math.pi / 180;

/// A point [east] and [north] metres from the journey's start
LatLng at(double east, double north) => LatLng(
  lat0 + north / mPerDegree,
  lon0 + east / (mPerDegree * math.cos(lat0 * math.pi / 180)),
);

/// From the door 200 m north to a stop, 2 km east on route 7 calling at
/// [stops] on the way, then 200 m south to the door
Journey journey({int? veh = planned, List<int>? stops}) => Journey(
  dep: 0,
  arr: 0,
  rides: 1,
  live: veh != null,
  confidence: Confidence.live,
  legs: [
    Leg(kind: 'walk', dep: 0, arr: 0, a: -1, b: 1, pts: [at(0, 0), at(0, 200)]),
    Leg(
      kind: 'ride',
      dep: 0,
      arr: 0,
      a: 1,
      b: 2,
      route: route,
      veh: veh,
      stops: stops,
      pts: [at(0, 200), at(1000, 200), at(2000, 200)],
    ),
    Leg(
      kind: 'walk',
      dep: 0,
      arr: 0,
      a: 2,
      b: -1,
      pts: [at(2000, 200), at(2000, 0)],
    ),
  ],
);

/// Stop 1 is boarded at, 2 got off at, and 3 lies between them, 1200 m on
final catalog = Catalog(
  routes: const [],
  stops: [
    for (final (i, p) in [
      at(0, 0),
      at(0, 200),
      at(2000, 200),
      at(1200, 200),
    ].indexed)
      Stop(
        id: 's$i',
        name: '$i',
        code: '$i',
        lat: p.latitude,
        lon: p.longitude,
        routes: const [],
      ),
  ],
  index: const {},
  stopIndex: const {},
);

/// Drives a [Follower] one fix at a time, every [fixEveryMs]
class Trip {
  Trip(Journey j) : follower = Follower(j, catalog);

  final Follower follower;
  var t = 0;

  Progress fix(LatLng p, [List<Seen> seen = const [], double accuracy = 10]) {
    t += fixEveryMs;
    return follower.update(
      Fix(lat: p.latitude, lon: p.longitude, accuracy: accuracy, t: t),
      seen,
    );
  }

  /// Fixes at [from] moving [mps] east along the ride, [n] of them, with
  /// vehicles placed by [seen] at each
  Progress east(
    double from,
    double mps,
    int n, {
    List<Seen> Function(double east) seen = none,
  }) {
    late Progress p;
    for (var k = 0; k < n; k++) {
      final x = from + mps * k * fixEveryMs / 1000;
      p = fix(at(x, 200), seen(x));
    }
    return p;
  }
}

List<Seen> none(double _) => const [];

/// The second ride's route and vehicle, and when it is timetabled to leave
const nextRoute = 9;
const next = 52;
const nextDep = 1000;

/// Metres a second: walking, and hurrying at twice that
const mps = 1.0;
const hurryMps = 2 * mps;

/// The journey above, but from the end of the ride 200 m on north to a stop
/// on route 9, 2 km east on it and 200 m back south to the door
Journey changing() {
  final j = journey();
  return Journey(
    dep: 0,
    arr: 0,
    rides: 2,
    live: true,
    confidence: Confidence.live,
    legs: [
      ...j.legs.take(2),
      Leg(
        kind: 'walk',
        dep: 0,
        arr: 0,
        a: 2,
        b: 4,
        pts: [at(2000, 200), at(2000, 400)],
      ),
      Leg(
        kind: 'ride',
        dep: nextDep,
        arr: 0,
        a: 4,
        b: 5,
        route: nextRoute,
        veh: next,
        pts: [at(2000, 400), at(4000, 400)],
      ),
      Leg(
        kind: 'walk',
        dep: 0,
        arr: 0,
        a: 5,
        b: -1,
        pts: [at(4000, 400), at(4000, 200)],
      ),
    ],
  );
}

/// The predictions: each stop's vehicle and when it gets there
Due predicted([List<(int, int, int)> says = const []]) =>
    (stop, veh) => says
        .where((s) => s.$1 == stop && s.$2 == veh)
        .map((s) => s.$3)
        .firstOrNull;

const riding = Stage(StageKind.ride, 1, planned);

/// Reach [late] seconds after the vehicle leaves at the usual pace, and
/// [hurriedLate] at the hurrying one
Reach reach(double late, [double? hurriedLate, bool live = true]) => Reach(
  leg: 3,
  dep: nextDep.toDouble(),
  live: live,
  from: nextDep - 120.0,
  walk: 300,
  usual: nextDep + late,
  hurried: nextDep + (hurriedLate ?? late),
);

Seen vehicle(int id, double east, {int onRoute = route}) {
  final p = at(east, 200);
  return Seen(id: id, route: onRoute, lat: p.latitude, lon: p.longitude);
}

/// [j] from its first ride on, begun on board or not
Journey fromRide(Journey j, {required bool aboard}) => Journey(
  dep: j.dep,
  arr: j.arr,
  rides: j.rides,
  live: j.live,
  confidence: j.confidence,
  legs: j.legs.sublist(1),
  aboard: aboard,
);

/// Walks the first leg to the stop
Trip atStop(Journey j) {
  final trip = Trip(j);
  for (var n = 0.0; n <= 200; n += 25) {
    trip.fix(at(0, n));
  }
  return trip;
}

void main() {
  test('walking to the stop waits there for the ride', () {
    final trip = atStop(journey());
    final p = trip.fix(at(0, 200));
    expect(p.stage.kind, StageKind.wait);
    expect(p.stage.leg, 1);
  });

  test('standing beside a tram at the stop is not boarding it', () {
    final trip = atStop(journey());
    final p = trip.east(0, 0, 30, seen: (_) => [vehicle(planned, 5)]);
    expect(p.stage.kind, StageKind.wait);
  });

  test('riding away with the tram boards it, within a few fixes', () {
    final trip = atStop(journey());
    trip.east(0, 0, 5, seen: (_) => [vehicle(planned, 0)]);
    final p = trip.east(0, 8, 8, seen: (x) => [vehicle(planned, x - 20)]);
    expect(p.stage.kind, StageKind.ride);
    expect(p.stage.veh, planned);
  });

  test('another vehicle of the route is picked when it is the one riding', () {
    final trip = atStop(journey());
    final p = trip.east(
      0,
      8,
      10,
      seen: (x) => [vehicle(planned, 900), vehicle(12, x + 15)],
    );
    expect(p.stage.kind, StageKind.ride);
    expect(p.stage.veh, 12);
  });

  test('the planned tram left standing at the stop is not the one ridden', () {
    final trip = atStop(journey());
    final p = trip.east(
      0,
      8,
      10,
      seen: (x) => [vehicle(planned, 0), vehicle(12, x + 15)],
    );
    expect(p.stage.kind, StageKind.ride);
    expect(p.stage.veh, 12);
  });

  test(
    'a tram drawn standing as it leaves is matched once it is drawn moving',
    () {
      final trip = atStop(journey());
      // The map keeps a vehicle where it stood until a fix shows it moving,
      // which reaches the server some 10-20 s after it pulled away, and then
      // draws it a little behind
      List<Seen> late(double x) => [vehicle(planned, x < 160 ? 0 : x - 60)];
      var p = trip.east(0, 8, 10, seen: late);
      expect(p.stage.kind, StageKind.ride);
      expect(p.stage.veh, isNull);
      p = trip.east(160, 8, 10, seen: late);
      expect(p.stage.veh, planned);
    },
  );

  test('the planned vehicle wins over another also keeping pace', () {
    final trip = atStop(journey());
    final p = trip.east(
      0,
      8,
      10,
      seen: (x) => [vehicle(12, x + 5), vehicle(planned, x + 40)],
    );
    expect(p.stage.veh, planned);
  });

  test('a vehicle of another route keeping pace is not the ride', () {
    final trip = atStop(journey());
    final p = trip.east(0, 8, 10, seen: (x) => [vehicle(5, x, onRoute: 99)]);
    expect(p.stage.kind, StageKind.ride);
    expect(p.stage.veh, isNull);
  });

  test('walking along the line is not riding it', () {
    final trip = atStop(journey());
    final p = trip.east(0, 1.6, 25, seen: (x) => [vehicle(planned, x)]);
    expect(p.stage.kind, StageKind.wait);
  });

  test('one jump of the GPS ahead is not a ride', () {
    final trip = atStop(journey());
    trip.east(0, 0, 5);
    final p = trip.fix(at(160, 200));
    expect(p.stage.kind, StageKind.wait);
  });

  test('a vague fix changes nothing', () {
    final trip = atStop(journey());
    trip.east(0, 0, 3);
    final p = trip.east(0, 8, 10, seen: (x) => [vehicle(planned, x)]);
    final still = trip.fix(at(1990, 200), const [], 200);
    expect(still.stage.kind, p.stage.kind);
    expect(still.left, p.left);
  });

  test('a fix older than the last changes nothing', () {
    final trip = atStop(journey());
    final p = trip.east(0, 8, 10, seen: (x) => [vehicle(planned, x)]);
    trip.t -= 3 * fixEveryMs;
    final late = trip.fix(at(0, 200));
    expect(late.stage.kind, p.stage.kind);
    expect(late.left, p.left);
  });

  test('a ride on a timetable vehicle boards on movement alone', () {
    final trip = atStop(journey(veh: null));
    final p = trip.east(0, 8, 10);
    expect(p.stage.kind, StageKind.ride);
    expect(p.stage.veh, isNull);
  });

  test('a ridden vehicle that drops out is found again', () {
    final trip = atStop(journey());
    trip.east(0, 8, 10, seen: (x) => [vehicle(planned, x)]);
    final p = trip.east(160, 8, 12, seen: (x) => [vehicle(12, x + 10)]);
    expect(p.stage.kind, StageKind.ride);
    expect(p.stage.veh, 12);
  });

  test('a ridden vehicle whose id comes back on another route is let go', () {
    // A second ride on route 99, so the follower watches that route too
    final j = journey();
    final transfer = Journey(
      dep: 0,
      arr: 0,
      rides: 2,
      live: true,
      confidence: Confidence.live,
      legs: [
        ...j.legs.take(2),
        Leg(kind: 'walk', dep: 0, arr: 0, a: 2, b: 3, pts: [at(2000, 200)]),
        Leg(
          kind: 'ride',
          dep: 0,
          arr: 0,
          a: 3,
          b: 4,
          route: 99,
          pts: [at(2000, 200), at(2000, 2000)],
        ),
        Leg(kind: 'walk', dep: 0, arr: 0, a: 4, b: -1, pts: [at(2000, 2000)]),
      ],
    );
    final trip = atStop(transfer);
    trip.east(0, 8, 10, seen: (x) => [vehicle(planned, x)]);
    final p = trip.east(
      160,
      8,
      6,
      seen: (x) => [vehicle(planned, x, onRoute: 99)],
    );
    expect(p.stage.kind, StageKind.ride);
    expect(p.stage.veh, isNull);
  });

  test(
    'getting ready starts at the last stop before the one to get off at',
    () {
      final trip = atStop(journey(stops: [3]));
      var p = trip.east(0, 8, 70, seen: (x) => [vehicle(planned, x)]);
      expect(p.stage.kind, StageKind.ride);
      expect(p.soon, isFalse);
      p = trip.east(1120, 8, 4, seen: (x) => [vehicle(planned, x)]);
      expect(p.soon, isTrue);
    },
  );

  test('a ride of one stop is getting ready from boarding', () {
    final trip = atStop(journey(stops: const []));
    final p = trip.east(0, 8, 10, seen: (x) => [vehicle(planned, x)]);
    expect(p.stage.kind, StageKind.ride);
    expect(p.soon, isTrue);
  });

  test('without the stops on the way, getting ready is 400 m out', () {
    final trip = atStop(journey());
    var p = trip.east(0, 8, 100, seen: (x) => [vehicle(planned, x)]);
    expect(p.stage.kind, StageKind.ride);
    expect(p.soon, isFalse);
    p = trip.east(1600, 8, 3, seen: (x) => [vehicle(planned, x)]);
    expect(p.soon, isTrue);
  });

  test('getting off at the stop walks the rest, then arrives', () {
    final trip = atStop(journey());
    trip.east(0, 8, 250, seen: (x) => [vehicle(planned, math.min(x, 2000))]);
    var p = trip.east(2000, 0, 10);
    expect(p.stage.kind, StageKind.walk);
    expect(p.stage.leg, 2);
    expect(p.passed, isFalse);
    for (var n = 200.0; n >= 0; n -= 25) {
      p = trip.fix(at(2000, n));
    }
    expect(p.stage.kind, StageKind.arrived);
  });

  test('staying on past the stop says so', () {
    final trip = atStop(journey());
    trip.east(0, 8, 245, seen: (x) => [vehicle(planned, x)]);
    final p = trip.east(1960, 8, 30);
    expect(p.stage.kind, StageKind.ride);
    expect(p.passed, isTrue);
  });

  test('a stop dwelt at and then left on the vehicle says so on the walk', () {
    final trip = atStop(journey());
    trip.east(0, 8, 250);
    trip.east(2000, 0, 10);
    final p = trip.east(2000, 8, 25);
    expect(p.stage.kind, StageKind.walk);
    expect(p.passed, isTrue);
  });

  test(
    'a journey begun on board starts riding its vehicle, then walks the rest',
    () {
      final trip = Trip(fromRide(journey(), aboard: true));
      var p = trip.fix(at(0, 200), [vehicle(planned, 0)]);
      expect(
        (p.stage.kind, p.stage.leg, p.stage.veh),
        (StageKind.ride, 0, planned),
      );
      trip.east(0, 8, 250, seen: (x) => [vehicle(planned, math.min(x, 2000))]);
      p = trip.east(2000, 0, 10);
      expect((p.stage.kind, p.stage.leg), (StageKind.walk, 1));
    },
  );

  test('a journey not begun on board waits for its first ride', () {
    final trip = Trip(fromRide(journey(), aboard: false));
    expect(trip.fix(at(0, 200)).stage.kind, StageKind.wait);
  });

  test('a journey without lines cannot be followed', () {
    final j = journey();
    expect(followable(j), isTrue);
    expect(
      followable(
        Journey(
          dep: 0,
          arr: 0,
          rides: 0,
          live: false,
          confidence: Confidence.live,
          legs: const [Leg(kind: 'walk', dep: 0, arr: 0, a: -1, b: -1)],
        ),
      ),
      isFalse,
    );
  });
  group('the next connection', () {
    test('walking to the stop is timed from the metres left', () {
      final trip = Trip(changing());
      trip.fix(at(0, 50));

      final r = trip.follower.reach(predicted(), 0, mps, hurryMps)!;

      expect(r.leg, 1);
      expect(r.usual, closeTo(150, 1e-6));
      expect(r.hurried, closeTo(75, 1e-6));
      expect(r.live, isFalse);
    });

    test(
      'on a ride the change is timed from when the vehicle ridden gets off',
      () {
        const off = 700;
        final follower = Follower(changing(), catalog, riding);

        final r = follower.reach(
          predicted([(2, planned, off), (4, next, 950)]),
          0,
          mps,
          hurryMps,
        )!;

        expect((r.leg, r.dep, r.live), (3, 950, true));
        expect(r.usual, closeTo(off + 200, 1e-6));
        expect(r.hurried, closeTo(off + 100, 1e-6));
      },
    );

    test('an untracked next ride goes by its timetable', () {
      final follower = Follower(changing(), catalog, riding);

      final r = follower.reach(predicted([(2, planned, 0)]), 0, mps, hurryMps)!;

      expect(r.dep, nextDep);
      expect(r.live, isFalse);
    });

    test('nothing is said while waiting, or riding a vehicle not known', () {
      final due = predicted([(2, planned, 0)]);

      for (final stage in const [
        Stage(StageKind.wait, 1),
        Stage(StageKind.ride, 1),
        Stage(StageKind.ride, 3, next),
      ]) {
        expect(
          Follower(changing(), catalog, stage).reach(due, 0, mps, hurryMps),
          isNull,
        );
      }
    });

    test('a resumed journey starts where it was', () {
      expect(Follower(changing(), catalog, riding).progress.stage, riding);
    });

    test(
      'on time, by hurrying, by the grace of a tracked vehicle, or missed',
      () {
        expect(judge(reach(0)), CatchKind.ok);
        expect(judge(reach(1, 0)), CatchKind.hurry);
        expect(judge(reach(30, 0)), CatchKind.hurry);
        expect(judge(reach(30, graceS)), CatchKind.hurry);
        expect(judge(reach(30, graceS, false)), CatchKind.missed);
        expect(judge(reach(30, graceS + 1)), CatchKind.missed);
      },
    );

    test('a worse word waits until it has held, a better one does not', () {
      final watch = Watch();
      // Far enough ahead for its prediction to still be jumpy
      const now = nextDep - 600.0;

      expect(watch.update(reach(30), riding, now).kind, CatchKind.ok);
      expect(watch.update(reach(30), riding, now + 5).kind, CatchKind.ok);
      final said = watch.update(reach(30), riding, now + 10);
      expect(
        (said.kind, said.leg, said.dep, said.riding, said.kmh),
        (CatchKind.missed, 3, nextDep, true, null),
      );
      expect(watch.update(reach(0), riding, now + 11).kind, CatchKind.ok);
    });

    test('one jumpy prediction is not news', () {
      final watch = Watch();
      const now = nextDep - 600.0;

      watch.update(reach(30), riding, now);
      watch.update(reach(0), riding, now + 5);

      expect(watch.update(reach(30), riding, now + 10).kind, CatchKind.ok);
    });

    test('close to leaving a worse word is said at once', () {
      expect(
        Watch().update(reach(30), riding, nextDep - 60.0).kind,
        CatchKind.missed,
      );
    });

    test('hurrying is urged on foot, and only warned of on a ride', () {
      const now = nextDep - 60.0;
      const walking = Stage(StageKind.walk, 2);

      expect(Watch().update(reach(30, 0), riding, now).riding, isTrue);
      expect(Watch().update(reach(30, 0), walking, now).riding, isFalse);
    });

    test('a word about one ride is not said of the next', () {
      final watch = Watch();
      const now = nextDep - 60.0;
      final hurry = watch.update(
        reach(30, 0),
        const Stage(StageKind.walk, 2),
        now,
      );
      // A change further on, far enough ahead for its prediction to be jumpy
      const later = nextDep + 600.0;
      const after = Reach(
        leg: 5,
        dep: later,
        live: true,
        from: now,
        walk: 300,
        usual: later + 30,
        hurried: later + 30,
      );

      expect(hurry.kind, CatchKind.hurry);
      expect(
        watch.update(after, const Stage(StageKind.ride, 3, next), now + 1).kind,
        CatchKind.ok,
      );
    });

    test('waiting at the stop of a missed ride still has it missed', () {
      final watch = Watch();
      watch.update(reach(30), const Stage(StageKind.walk, 2), nextDep - 60.0);

      expect(
        watch
            .update(null, const Stage(StageKind.wait, 3), nextDep.toDouble())
            .kind,
        CatchKind.missed,
      );
      expect(
        watch
            .update(
              null,
              const Stage(StageKind.ride, 3, next),
              nextDep.toDouble(),
            )
            .kind,
        CatchKind.ok,
      );
    });
  });

  group('the pace hurrying needs', () {
    test("keeps half a change's slack, more the further ahead it leaves", () {
      expect(margin(0), 30);
      expect(margin(300), closeTo(56.25, 1e-9));
      expect(margin(9999), 150);
    });

    test('walks there with the margin to spare, rounded up to a step', () {
      // 300 m in 300 - 56.25 s is 4.43 km/h
      expect(needKmh(300, 0, 300), 4.5);
    });

    test('is timed from when the ride was forecast, not from setting off', () {
      // off a ride at 600 for a ride leaving at 900: forecast 900 s ahead
      expect(needKmh(300, 600, 900, 0), greaterThan(needKmh(300, 600, 900)!));
    });

    test('drops the margin rather than ask for more than a run', () {
      // with the margin 66 s for 300 m, 16.4 km/h; right at the ride 10.8
      expect(needKmh(300, 0, 100), 11);
    });

    test('is nothing once no time is left, or with nothing to walk', () {
      expect(needKmh(300, 100, 100), isNull);
      expect(needKmh(0, 0, 300), isNull);
    });

    test('of a planned option is read off its first walk', () {
      final pts = [at(0, 0), at(0, 300)];
      expect(along(pts), closeTo(300, 1e-6));
      final option = Journey(
        dep: 0,
        arr: 600,
        rides: 1,
        live: false,
        confidence: Confidence.live,
        legs: [
          Leg(kind: 'walk', dep: 0, arr: 300, a: -1, b: 0, pts: pts),
          const Leg(kind: 'ride', dep: 300, arr: 600, a: 0, b: 1),
        ],
      );
      expect(plannedKmh(option), 4.5);
    });

    test('is said with a hurry, and not with a miss', () {
      const walking = Stage(StageKind.walk, 2);
      final hurry = Watch().update(reach(30, 0), walking, nextDep - 120.0);
      final missed = Watch().update(reach(30), walking, nextDep - 60.0);

      expect(
        (hurry.kind, hurry.kmh),
        (CatchKind.hurry, needKmh(300, nextDep - 120.0, nextDep.toDouble())),
      );
      expect((missed.kind, missed.kmh), (CatchKind.missed, null));
    });
  });
}
