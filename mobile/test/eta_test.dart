import 'package:flutter_test/flutter_test.dart';

import 'package:commuterlviv/src/eta.dart';

void main() {
  // The bug this pins: `t` read as a countdown rather than as an instant put
  // "29814221 min" on the phone, which is unix time divided by sixty
  test('the countdown is against the clock, not from zero', () {
    final now = DateTime.utc(2026, 9, 8, 10, 0);
    final t = now.millisecondsSinceEpoch ~/ 1000;

    expect(countdown(t, now: now), 'now');
    expect(countdown(t + 29, now: now), 'now');
    expect(countdown(t + 60, now: now), '1 min');
    expect(countdown(t + 90, now: now), '2 min');
    expect(countdown(t + 600, now: now), '10 min');
    expect(countdown(t - 300, now: now), 'now');
  });
}
