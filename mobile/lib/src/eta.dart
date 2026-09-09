/// How long until an arrival, said the way a rider would say it.
///
/// A port of `web/src/lib/eta.ts`, thresholds included, so the two clients
/// never disagree about whether something is "now".
library;

/// The wire's `t` is an absolute unix time in seconds, not a countdown: the
/// service sends when the vehicle calls, and the client subtracts its own clock
String countdown(int t, {DateTime? now}) {
  final s = t - (now ?? DateTime.now()).millisecondsSinceEpoch / 1000;
  if (s < 30) return 'now';
  if (s < 90) return '1 min';
  return '${(s / 60).round()} min';
}
