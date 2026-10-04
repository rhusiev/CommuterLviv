import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:commuterlviv/src/api.dart';
import 'package:commuterlviv/src/follow_card.dart';
import 'package:commuterlviv/src/here.dart';
import 'package:commuterlviv/src/live.dart';
import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/strings.dart';

const lat0 = 49.84;
const lon0 = 24.03;
const fixEveryMs = 2000;
const rideM = 2000.0;
const mPerDegree = 6371000 * math.pi / 180;

LatLng at(double east, double north) => LatLng(
  lat0 + north / mPerDegree,
  lon0 + east / (mPerDegree * math.cos(lat0 * math.pi / 180)),
);

/// 200 m north to stop 0, a timetable ride 2 km east to stop 1, 200 m south
final journey = Journey(
  dep: 0,
  arr: 0,
  rides: 1,
  live: false,
  confidence: Confidence.live,
  legs: [
    Leg(kind: 'walk', dep: 0, arr: 0, a: -1, b: 0, pts: [at(0, 0), at(0, 200)]),
    Leg(
      kind: 'ride',
      dep: 0,
      arr: 0,
      a: 0,
      b: 1,
      route: 0,
      pts: [at(0, 200), at(rideM, 200)],
    ),
    Leg(
      kind: 'walk',
      dep: 0,
      arr: 0,
      a: 1,
      b: -1,
      pts: [at(rideM, 200), at(rideM, 0)],
    ),
  ],
);

final catalog = Catalog(
  routes: const [
    TransitRoute(id: 'r7', short: '7', long: 'A to B', type: 'tram'),
  ],
  stops: [
    for (final (i, p) in [at(0, 200), at(rideM, 200)].indexed)
      Stop(
        id: 's$i',
        name: 'Stop $i',
        code: '$i',
        lat: p.latitude,
        lon: p.longitude,
        routes: const [0],
      ),
  ],
  index: const {'r7': 0},
  stopIndex: const {'s0': 0, 's1': 1},
);

/// A [Here] fed by hand, which keeps what was said on the notification
class FakeHere extends Here {
  FakeHere() : super(onFirstFix: (_) {});

  final notices = <String>[];
  final alerts = <String>[];
  var t = 0;

  void move(double east, double north) {
    t += fixEveryMs;
    fix = Fix(at(east, north), 10, t);
    state = Locating.on;
    notifyListeners();
  }

  @override
  Future<bool> away(
    bool on, {
    required String channel,
    required String alerts,
  }) async => true;

  @override
  Future<bool> notice(String title, String text, {bool alert = false}) async {
    notices.add(title);
    if (alert) alerts.add(title);
    return true;
  }
}

Future<FakeHere> pump(WidgetTester tester, {required bool away}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final api = await Api.open();
  final here = FakeHere();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FollowCard(
          catalog: catalog,
          journey: journey,
          live: Live(api, onRenewed: () {}),
          here: here,
          away: away,
          onEnd: () {},
        ),
      ),
    ),
  );
  return here;
}

/// Walks to the stop, waits, rides at 8 m/s to the end, and walks to the door
Future<void> travel(WidgetTester tester, FakeHere here) async {
  Future<void> to(double east, double north) async {
    here.move(east, north);
    await tester.pump();
  }

  for (var n = 0.0; n <= 200; n += 25) {
    await to(0, n);
  }
  for (var k = 0; k < 10; k++) {
    await to(0, 200);
  }
  for (var x = 0.0; x <= rideM; x += 16) {
    await to(x, 200);
  }
  for (var k = 0; k < 10; k++) {
    await to(rideM, 200);
  }
  for (var n = 200.0; n >= 0; n -= 25) {
    await to(rideM, n);
  }
  for (var k = 0; k < 5; k++) {
    await to(rideM, 0);
  }
}

void main() {
  testWidgets('away, the notification sounds once to get off and once on '
      'arrival', (tester) async {
    final here = await pump(tester, away: true);
    await travel(tester, here);
    expect(here.alerts, [txt.offSoon('Stop 1'), txt.arrived]);
  });

  testWidgets('away, a fix that changes nothing said is not sent on', (
    tester,
  ) async {
    final here = await pump(tester, away: true);
    for (var k = 0; k < 10; k++) {
      here.move(0, 0);
      await tester.pump();
    }
    expect(here.notices, hasLength(1));
  });

  testWidgets('on screen, nothing is said on a notification', (tester) async {
    final here = await pump(tester, away: false);
    await travel(tester, here);
    expect(here.notices, isEmpty);
  });
}
