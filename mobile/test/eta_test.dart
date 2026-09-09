import 'package:flutter_test/flutter_test.dart';

import 'package:commuterlviv/src/eta.dart';
import 'package:commuterlviv/src/strings.dart';

void main() {
  // The bug this pins: `t` read as a countdown rather than as an instant put
  // "29814221 min" on the phone, which is unix time divided by sixty
  test('the countdown is against the clock, not from zero', () {
    final now = DateTime.utc(2026, 9, 8, 10, 0);
    final t = now.millisecondsSinceEpoch ~/ 1000;

    // Against the dictionary rather than against English: the thresholds are
    // what this tests, and the app launches in Ukrainian
    expect(countdown(t, now: now), txt.now);
    expect(countdown(t + 29, now: now), txt.now);
    expect(countdown(t + 60, now: now), txt.oneMinute);
    expect(countdown(t + 90, now: now), txt.minutes(2));
    expect(countdown(t + 600, now: now), txt.minutes(10));
    expect(countdown(t - 300, now: now), txt.now);
  });
}
