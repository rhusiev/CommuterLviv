/// What the service says about the city and about the account. Mirrors
/// `web/src/lib/types.ts`; routes and stops are addressed by their index in
/// these lists everywhere on the wire.
library;

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

  /// `bus`, `tram` or `trolleybus` - what `gtfs.vehicle_type` reads off the
  /// route's short name, not a GTFS `route_type` number
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

  /// Route id to its index, which is what the socket filter speaks
  final Map<String, int> index;

  /// Stop id to its index, for the same reason: what is stored is an id and
  /// what is sent is a position
  final Map<String, int> stopIndex;
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

class Sets {
  const Sets({required this.sets, required this.active, required this.pins});

  factory Sets.fromJson(Map<String, dynamic> j) => Sets(
    sets: [
      for (final s in j['sets'] as List)
        RouteSet.fromJson(s as Map<String, dynamic>),
    ],
    active: j['active'] as String?,
    pins: [for (final p in (j['pins'] as List?) ?? const []) p as String],
  );

  final List<RouteSet> sets;
  final String? active;

  /// Pinned stops, by feed id. A catalog position means nothing once the city
  /// changes its feed and the catalog is rebuilt around it
  final List<String> pins;
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

/// The reverse of an [Arrival]: one vehicle, and a stop ahead of it
class Call {
  const Call({required this.stop, required this.route, required this.t});

  factory Call.fromJson(Map<String, dynamic> j) =>
      Call(stop: j['stop'] as int, route: j['route'] as int, t: j['t'] as int);

  final int stop;
  final int route;

  /// Unix seconds at which it gets there
  final int t;
}

class Arrival {
  const Arrival({required this.route, required this.veh, required this.t});

  factory Arrival.fromJson(Map<String, dynamic> j) =>
      Arrival(route: j['route'] as int, veh: j['veh'] as int, t: j['t'] as int);

  final int route;
  final int veh;

  /// Unix seconds at which it calls here - an instant, not a countdown
  final int t;
}

/// One unbroken movement of a planned journey. `a` and `b` are catalog stop
/// indexes, or -1 for the door at either end; a walk has no route. `live` says
/// the ride is a vehicle the model can see rather than a timetable entry.
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
  );

  final String kind;
  final int dep;
  final int arr;
  final int a;
  final int b;
  final int? route;
  final int? veh;
  final bool live;

  bool get walking => kind == 'walk';
}

class Journey {
  const Journey({
    required this.dep,
    required this.arr,
    required this.rides,
    required this.live,
    required this.legs,
  });

  factory Journey.fromJson(Map<String, dynamic> j) => Journey(
    dep: j['dep'] as int,
    arr: j['arr'] as int,
    rides: j['rides'] as int,
    live: j['live'] as bool,
    legs: [
      for (final l in j['legs'] as List)
        Leg.fromJson(l as Map<String, dynamic>),
    ],
  );

  final int dep;
  final int arr;
  final int rides;

  /// True when every ride in it is a vehicle the model can see
  final bool live;
  final List<Leg> legs;
}
