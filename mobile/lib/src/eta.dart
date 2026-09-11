/// How long until an arrival, said the way a rider would say it.
library;

import 'strings.dart';

/// The wire's `t` is absolute unix seconds, not a countdown.
String countdown(int t, {DateTime? now}) {
  final s = t - (now ?? DateTime.now()).millisecondsSinceEpoch / 1000;
  if (s < 30) return txt.now;
  if (s < 90) return txt.oneMinute;
  return txt.minutes((s / 60).round());
}
