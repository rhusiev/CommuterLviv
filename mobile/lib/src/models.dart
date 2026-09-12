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
  const Arrival({required this.route, required this.veh, required this.t});

  factory Arrival.fromJson(Map<String, dynamic> j) =>
      Arrival(route: j['route'] as int, veh: j['veh'] as int, t: j['t'] as int);

  final int route;
  final int veh;

  /// Unix seconds, an instant rather than a countdown.
  final int t;
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

  bool get walking => kind == 'walk';
}

/// What a ride rests on: a vehicle being tracked, the timetable on a route that
/// is running, or the timetable on one nothing has been seen running on.
enum Confidence { live, schedule, quiet }

/// Absent is a leg that rests on nothing in particular - a walk, or a server
/// from before this field. An unknown word reads as the timetable rather than
/// as a promise of a tracked vehicle.
Confidence confidenceOf(Object? word) => switch (word) {
  null || 'live' => Confidence.live,
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
  });

  factory Journey.fromJson(Map<String, dynamic> j) => Journey(
    dep: j['dep'] as int,
    arr: j['arr'] as int,
    rides: j['rides'] as int,
    live: j['live'] as bool,
    confidence: confidenceOf(j['confidence']),
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
  final List<Leg> legs;
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
