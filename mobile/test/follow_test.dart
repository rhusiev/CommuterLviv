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

/// From the door 200 m north to a stop, 2 km east on route 7, then 200 m
/// south to the door
Journey journey({int? veh = planned}) => Journey(
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

/// Drives a [Follower] one fix at a time, every [fixEveryMs]
class Trip {
  Trip(Journey j) : follower = Follower(j);

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

Seen vehicle(int id, double east, {int onRoute = route}) {
  final p = at(east, 200);
  return Seen(id: id, route: onRoute, lat: p.latitude, lon: p.longitude);
}

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
}
