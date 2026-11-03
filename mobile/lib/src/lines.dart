/// What the Lines tab works out from the shapes and the arrivals; the web's
/// `lib/lines.ts`.
library;

import 'package:latlong2/latlong.dart';

import 'models.dart';

/// One way a line runs, by the stops it calls at in order.
typedef Direction = ({int dir, List<int> stops});

/// One stop of a line: this route's next arrival there, and the vehicles whose
/// soonest stop on the line it is.
typedef LineRow = ({int stop, Arrival? next, List<int> vehs});

/// How many lines opened lately the Lines tab offers again.
const recentLines = 5;

/// Around a five-minute walk. Chosen, not derived.
const nearLinesM = 500;

/// Each way the route runs, once: of several shapes one way, the one calling
/// at the most stops, since the others are short workings of it.
List<Direction> directions(RouteShape? shape) {
  final best = <int, List<int>>{};
  for (final line in shape?.lines ?? const <RouteLine>[]) {
    if (line.stops.length > (best[line.dir]?.length ?? 0)) {
      best[line.dir] = line.stops;
    }
  }
  final dirs = best.keys.toList()..sort();
  return [for (final d in dirs) (dir: d, stops: best[d]!)];
}

/// The stops of one direction, each with what [route] has due there. A vehicle
/// is shown at the stop it reaches soonest, which is the one it is heading for;
/// one still finishing its previous trip (`planned`) is not on the line yet.
List<LineRow> lineRows(
  List<int> stops,
  Map<int, List<Arrival>> arrivals,
  int route,
) {
  final here = [
    for (final s in stops)
      [
        for (final a in arrivals[s] ?? const <Arrival>[])
          if (a.route == route) a,
      ],
  ];
  final soonest = <int, ({int t, int row})>{};
  for (var row = 0; row < here.length; row++) {
    for (final a in here[row]) {
      if (a.planned) continue;
      final held = soonest[a.veh];
      if (held == null || a.t < held.t) soonest[a.veh] = (t: a.t, row: row);
    }
  }
  final vehs = [for (final _ in stops) <int>[]];
  for (final MapEntry(key: veh, value: (:row, t: _)) in soonest.entries) {
    vehs[row].add(veh);
  }
  return [
    for (var i = 0; i < stops.length; i++)
      (stop: stops[i], next: here[i].firstOrNull, vehs: vehs[i]),
  ];
}

/// Routes calling at any stop within [radius] metres of [at].
Set<int> routesNear(Catalog catalog, LatLng at, num radius) {
  const distance = Distance();
  return {
    for (final s in catalog.stops)
      if (distance(at, LatLng(s.lat, s.lon)) <= radius) ...s.routes,
  };
}

/// [id] first, then the rest as they were, [recentLines] at most.
List<String> opened(List<String> recent, String id) =>
    [id, ...recent.where((r) => r != id)].take(recentLines).toList();

/// Around now means within this of it, either way. Chosen, not derived.
const howOftenAroundS = 30 * 60;

/// A line's day at one stop: its first and last departure and, around now,
/// the typical gap between them in seconds - null outside its hours or where
/// it leaves too seldom to say.
typedef Hours = ({int first, int last, int? every});

/// [dep] is the day's departures from the stop, soonest first.
Hours? lineHours(List<int> dep, int now) {
  if (dep.isEmpty) return null;
  final near = [
    for (final t in dep)
      if ((t - now).abs() <= howOftenAroundS) t,
  ];
  final gaps = [for (var i = 1; i < near.length; i++) near[i] - near[i - 1]]
    ..sort();
  return (
    first: dep.first,
    last: dep.last,
    every: gaps.isEmpty ? null : gaps[gaps.length ~/ 2],
  );
}
