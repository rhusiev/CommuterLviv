/// Waiting on a fake server that answers in real time, from a widget test
/// whose clock is fake.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _step = Duration(milliseconds: 10);
const _steps = 100;

/// Lets requests reach a real server for the rest of the test: the test
/// binding otherwise answers every one with 400.
void allowRealHttp() {
  final faked = HttpOverrides.current;
  HttpOverrides.global = null;
  addTearDown(() => HttpOverrides.global = faked);
}

/// Lets the fake server answer for a [_step] of real time, then moves the
/// clock on as far, so a dialog closing meanwhile gets to finish.
Future<void> _pumpStep(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(_step));
  await tester.pump(_step);
}

/// Pumps until [done] says so; fails if it never does.
Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < _steps && !done(); i++) {
    await _pumpStep(tester);
  }
  expect(done(), isTrue, reason: 'gave up waiting');
}

/// Pumps as long as [pumpUntil] would wait at most, for what must not come.
Future<void> pumpQuiet(WidgetTester tester) async {
  for (var i = 0; i < _steps; i++) {
    await _pumpStep(tester);
  }
}
