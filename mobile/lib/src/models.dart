/// What the service says about the city and the account. Routes and stops are
/// addressed by their index in these lists everywhere on the wire.
library;

import 'package:latlong2/latlong.dart';

class TransitRoute {
  const TransitRoute({
    required this.id,
    required this.short,
    required this.long,
    required this.type,
  });

  factory TransitRoute.fromJson(Map<String, dynamic> j) => TransitRoute(
    id: j['id'] as String,
    short: j['short'] as String,
    long: j['long'] as String,
    type: j['type'] as String,
  );

  final String id;
  final String short;
  final String long;

  /// `bus`, `tram` or `trolleybus`, not a GTFS `route_type` number.
  final String type;
}

class Stop {
  const Stop({
    required this.id,
    required this.name,
    required this.code,
    required this.lat,
    required this.lon,
    required this.routes,
  });

  factory Stop.fromJson(Map<String, dynamic> j) => Stop(
    id: j['id'] as String,
    name: j['name'] as String,
    code: j['code'] as String,
    lat: (j['lat'] as num).toDouble(),
    lon: (j['lon'] as num).toDouble(),
    routes: [for (final r in j['routes'] as List) r as int],
  );

  final String id;
  final String name;
  final String code;
  final double lat;
  final double lon;
  final List<int> routes;
}

class Catalog {
  const Catalog({
    required this.routes,
    required this.stops,
    required this.index,
    required this.stopIndex,
  });

  factory Catalog.fromJson(Map<String, dynamic> j) {
    final routes = [
      for (final r in j['routes'] as List)
        TransitRoute.fromJson(r as Map<String, dynamic>),
    ];
    final stops = [
      for (final s in j['stops'] as List)
        Stop.fromJson(s as Map<String, dynamic>),
    ];
    return Catalog(
      routes: routes,
      stops: stops,
      index: {for (var i = 0; i < routes.length; i++) routes[i].id: i},
      stopIndex: {for (var i = 0; i < stops.length; i++) stops[i].id: i},
    );
  }

  final List<TransitRoute> routes;
  final List<Stop> stops;

  final Map<String, int> index;

  final Map<String, int> stopIndex;

  /// Feed ids to positions in [routes] or [stops]; one the city dropped since
  /// the ids were stored does not resolve, and is left out.
  Iterable<int> routesAt(List<String> ids) =>
      ids.map((id) => index[id]).whereType<int>();

  List<int> stopsAt(List<String> ids) => [for (final id in ids) ?stopIndex[id]];
}

class RouteSet {
  const RouteSet({
    required this.id,
    required this.name,
    required this.routes,
    required this.ord,
  });

  factory RouteSet.fromJson(Map<String, dynamic> j) => RouteSet(
    id: j['id'] as String,
    name: j['name'] as String,
    routes: [for (final r in j['routes'] as List) r as String],
    ord: j['ord'] as int,
  );

  final String id;
  final String name;
  final List<String> routes;
  final int ord;
}

/// A saved place. The name is the identity: one place per name, server-side.
class Place {
  const Place({required this.name, required this.at});

  factory Place.fromJson(Map<String, dynamic> j) => Place(
    name: j['name'] as String,
    at: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
  );

  final String name;
  final LatLng at;

  Map<String, dynamic> toJson() => {
    'name': name,
    'lat': at.latitude,
    'lon': at.longitude,
  };
}

class Sets {
  const Sets({
    required this.sets,
    required this.active,
    required this.pins,
    required this.places,
  });

  factory Sets.fromJson(Map<String, dynamic> j) => Sets(
    sets: [
      for (final s in j['sets'] as List)
        RouteSet.fromJson(s as Map<String, dynamic>),
    ],
    active: j['active'] as String?,
    pins: [for (final p in (j['pins'] as List?) ?? const []) p as String],
    places: [
      for (final p in (j['places'] as List?) ?? const [])
        Place.fromJson(p as Map<String, dynamic>),
    ],
  );

  final List<RouteSet> sets;
  final String? active;

  /// Pinned stops, by feed id: catalog positions do not survive a rebuild.
  final List<String> pins;

  final List<Place> places;
}

class Me {
  const Me({required this.username, required this.sets});

  factory Me.fromJson(Map<String, dynamic> j) => Me(
    username: j['username'] as String,
    sets: Sets.fromJson(j['sets'] as Map<String, dynamic>),
  );

  final String username;
  final Sets sets;
}

class Call {
  const Call({required this.stop, required this.route, required this.t});

  factory Call.fromJson(Map<String, dynamic> j) =>
      Call(stop: j['stop'] as int, route: j['route'] as int, t: j['t'] as int);

  final int stop;
  final int route;

  /// Unix seconds.
  final int t;
}

class Arrival {
  const Arrival({
    required this.route,
    required this.veh,
    required this.t,
    this.planned = false,
  });

  factory Arrival.fromJson(Map<String, dynamic> j) => Arrival(
    route: j['route'] as int,
    veh: j['veh'] as int,
    t: j['t'] as int,
    planned: j['planned'] as bool? ?? false,
  );

  final int route;
  final int veh;

  /// Unix seconds, an instant rather than a countdown.
  final int t;

  /// A vehicle still finishing its previous trip: the time is its timetabled
  /// departure or when it can turn around, whichever is later
  final bool planned;
}

/// One leg of a planned journey. `a` and `b` are catalog stop indexes, or -1
/// for the door at either end; a walk has no route.
class Leg {
  const Leg({
    required this.kind,
    required this.dep,
    required this.arr,
    required this.a,
    required this.b,
    this.route,
    this.veh,
    this.live = false,
    this.confidence = Confidence.live,
    this.pts = const [],
    this.stops,
    this.backups = const [],
  });

  factory Leg.fromJson(Map<String, dynamic> j) => Leg(
    kind: j['kind'] as String,
    dep: j['dep'] as int,
    arr: j['arr'] as int,
    a: j['a'] as int,
    b: j['b'] as int,
    route: j['route'] as int?,
    veh: j['veh'] as int?,
    live: j['live'] as bool? ?? false,
    confidence: confidenceOf(j['confidence']),
    pts: [
      for (final p in j['pts'] as List<dynamic>? ?? const [])
        LatLng(
          ((p as List<dynamic>)[0] as num).toDouble(),
          (p[1] as num).toDouble(),
        ),
    ],
    stops: (j['stops'] as List<dynamic>?)?.cast<int>(),
    backups: [
      for (final b in j['backups'] as List<dynamic>? ?? const [])
        Backup.fromJson(b as Map<String, dynamic>),
    ],
  );

  final String kind;
  final int dep;
  final int arr;
  final int a;
  final int b;
  final int? route;
  final int? veh;
  final bool live;
  final Confidence confidence;

  /// Where the leg goes on the map: the footpath, or the ridden stretch
  final List<LatLng> pts;

  /// Catalog stops a ride calls at on the way, in order; null from an older
  /// service
  final List<int>? stops;

  /// Other ways to the door from where the ride boards, soonest first
  final List<Backup> backups;

  bool get walking => kind == 'walk';
}

/// Another way to the door from where a ride boards: the rides it takes, the
/// first leaving from there, and when it reaches the door
/// How fast you walk on the level, in km/h: the steps offered, and what is
/// assumed until you say, which is also the service's own.
const walkKmh = (min: 0.5, max: 8.0, step: 0.5, usual: 4.5);

class Backup {
  const Backup({
    required this.rides,
    required this.arr,
    this.walk = 0,
    this.planned = const [],
    this.option = -1,
  });

  factory Backup.fromJson(Map<String, dynamic> j) {
    final rides = [
      for (final r in j['rides'] as List<dynamic>) r as Map<String, dynamic>,
    ];
    return Backup(
      rides: [
        for (final r in rides) Leg.fromJson({...r, 'kind': 'ride'}),
      ],
      arr: j['arr'] as int,
      walk: j['walk'] as int? ?? 0,
      planned: [for (final r in rides) r['planned'] as bool? ?? false],
      option: j['option'] as int? ?? -1,
    );
  }

  final List<Leg> rides;
  final int arr;

  /// Seconds on foot.
  final int walk;

  /// Per ride, whether it is on a vehicle the journey rides too, further
  /// along - no help should that one not come.
  final List<bool> planned;

  /// The index in the plan's options of the one riding exactly these rides,
  /// or -1; an older service sends none.
  final int option;
}

/// What a ride rests on: a vehicle being tracked, one on a trip it is yet to set
/// off on, the timetable on a route that is running, or the timetable on one
/// nothing has been seen running on.
enum Confidence { live, terminus, schedule, quiet }

/// Absent is a leg that rests on nothing in particular - a walk, or a server
/// from before this field. An unknown word reads as the timetable rather than
/// as a promise of a tracked vehicle.
Confidence confidenceOf(Object? word) => switch (word) {
  null || 'live' => Confidence.live,
  'terminus' => Confidence.terminus,
  'quiet' => Confidence.quiet,
  _ => Confidence.schedule,
};

class Journey {
  const Journey({
    required this.dep,
    required this.arr,
    required this.rides,
    required this.live,
    required this.confidence,
    required this.legs,
    this.backup = 0,
  });

  factory Journey.fromJson(Map<String, dynamic> j) => Journey(
    dep: j['dep'] as int,
    arr: j['arr'] as int,
    rides: j['rides'] as int,
    live: j['live'] as bool,
    confidence: confidenceOf(j['confidence']),
    backup: j['backup'] as int? ?? 0,
    legs: [
      for (final l in j['legs'] as List)
        Leg.fromJson(l as Map<String, dynamic>),
    ],
  );

  final int dep;
  final int arr;
  final int rides;

  final bool live;

  /// The weakest ground any ride in it stands on.
  final Confidence confidence;

  /// Distinct routes repeating the weakest ride within half an hour of
  /// boarding it; 0 on a pure walk, or against an older service.
  final int backup;
  final List<Leg> legs;

  int get walking =>
      legs.where((l) => l.walking).fold(0, (s, l) => s + l.arr - l.dep);
}

/// What the options are sorted by. The whole walk goes last wherever changes
/// or backups are asked for, since it has neither to speak of.
enum Prefer {
  fastest,
  walk,
  changes,
  reliable;

  List<num> _score(Journey j) {
    num ride(num v) => j.rides == 0 ? double.infinity : v;
    // A minute on foot counts as two, so a ride from the door beats a slightly
    // earlier one behind a long walk
    final effort = j.arr + j.walking;
    return switch (this) {
      fastest => [j.arr, j.rides, j.walking],
      walk => [j.walking, j.arr, j.rides],
      changes => [ride(j.rides), effort],
      reliable => [ride(-j.backup), effort, j.rides],
    };
  }

  List<num> _backupScore(Backup b) {
    final effort = b.arr + b.walk;
    return switch (this) {
      fastest => [b.arr, b.rides.length, b.walk],
      walk => [b.walk, b.arr, b.rides.length],
      changes => [b.rides.length, effort],
      reliable => [
        b.planned.where((p) => p).length,
        b.rides.where((r) => !r.live).length,
        effort,
      ],
    };
  }

  List<Journey> ranked(List<Journey> options) => _order(options, _score);

  /// The [n] backups worth showing first, soonest first as sent: the best by
  /// this, then the best by each other preference, so one is there should this
  /// be the thing that fails, then the next best by this.
  List<Backup> shortlist(List<Backup> backups, {int n = 4}) {
    final picks = <Backup>{};
    for (final p in [this, ...values.where((p) => p != this)]) {
      final best = _order(backups, p._backupScore).firstOrNull;
      if (best != null && picks.length < n) picks.add(best);
    }
    for (final b in _order(backups, _backupScore)) {
      if (picks.length >= n) break;
      picks.add(b);
    }
    return [
      for (final b in backups)
        if (picks.contains(b)) b,
    ];
  }
}

/// Lowest score first, a tie settled by the next number and then by the order
/// given - List.sort is not stable.
List<T> _order<T>(List<T> items, List<num> Function(T) score) {
  final scored = [for (final (i, x) in items.indexed) (score(x), i, x)];
  scored.sort((a, b) {
    for (final (n, x) in a.$1.indexed) {
      final c = x.compareTo(b.$1[n]);
      if (c != 0) return c;
    }
    return a.$2.compareTo(b.$2);
  });
  return [for (final (_, _, x) in scored) x];
}

/// One row of the place search: an address or a point of interest in the city.
/// [where] is the line under the name, [kind] the OpenStreetMap value that made
/// it - `supermarket`, `bus_stop` and so on.
class Found {
  const Found({
    required this.name,
    required this.where,
    required this.at,
    required this.kind,
  });

  factory Found.fromJson(Map<String, dynamic> j) => Found(
    name: j['name'] as String,
    where: j['where'] as String? ?? '',
    at: LatLng((j['lat'] as num).toDouble(), (j['lon'] as num).toDouble()),
    kind: j['kind'] as String?,
  );

  final String name;
  final String where;
  final LatLng at;
  final String? kind;
}

/// The stretches of street the traffic numbers are measured on. Fixed for the
/// life of the service, so it is asked for once and kept.
class Streets {
  const Streets(this.lines);

  factory Streets.fromJson(Map<String, dynamic> j) => Streets([
    for (final line in j['lines'] as List)
      [
        for (final p in line as List)
          LatLng(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()),
      ],
  ]);

  final List<List<LatLng>> lines;
}

/// How each stretch is running: actual over timetabled travel time, so above 1
/// is slower than scheduled. Null where too little has been seen to say, and
/// parallel to [Streets.lines].
class Traffic {
  const Traffic({required this.t, required this.ratio});

  factory Traffic.fromJson(Map<String, dynamic> j) => Traffic(
    t: j['t'] as int,
    ratio: [for (final r in j['ratio'] as List) (r as num?)?.toDouble()],
  );

  final int t;
  final List<double?> ratio;
}

/// One run of a route, and which of the feed's two directions it is. The
/// direction is what tells a stretch run both ways from a one-way one, so the
/// chevrons on it can be drawn as two tracks rather than one.
class RouteLine {
  const RouteLine({required this.dir, required this.pts});

  factory RouteLine.fromJson(Map<String, dynamic> j) => RouteLine(
    dir: j['dir'] as int,
    pts: [
      for (final p in j['pts'] as List)
        LatLng(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()),
    ],
  );

  final int dir;
  final List<LatLng> pts;
}

class RouteShape {
  const RouteShape({required this.lines, required this.twoWay});

  factory RouteShape.fromJson(Map<String, dynamic> j) {
    final lines = [
      for (final line in j['lines'] as List)
        RouteLine.fromJson(line as Map<String, dynamic>),
    ];
    return RouteShape(
      lines: lines,
      twoWay: lines.any((l) => l.dir == 0) && lines.any((l) => l.dir == 1),
    );
  }

  final List<RouteLine> lines;

  /// Whether the route has runs both ways, and so wants two tracks of chevrons.
  final bool twoWay;
}

class Shapes {
  const Shapes(this.routes);

  factory Shapes.fromJson(Map<String, dynamic> j) => Shapes([
    for (final r in j['routes'] as List)
      RouteShape.fromJson(r as Map<String, dynamic>),
  ]);

  /// Parallel to `Catalog.routes`.
  final List<RouteShape> routes;
}
