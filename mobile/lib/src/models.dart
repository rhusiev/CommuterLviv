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

  final bool live;
  final List<Leg> legs;
}

/// Where a route goes and which way. A `twoWay` arrow marks a stretch the
/// route also runs the other way along.
class RouteArrow {
  const RouteArrow({
    required this.at,
    required this.heading,
    required this.twoWay,
  });

  /// `[lat, lon, heading, two-way]` on the wire.
  factory RouteArrow.fromJson(List<dynamic> j) => RouteArrow(
    at: LatLng((j[0] as num).toDouble(), (j[1] as num).toDouble()),
    heading: (j[2] as num).toDouble(),
    twoWay: j[3] == 1,
  );

  final LatLng at;
  final double heading;
  final bool twoWay;
}

class RouteShape {
  const RouteShape({required this.lines, required this.arrows});

  factory RouteShape.fromJson(Map<String, dynamic> j) => RouteShape(
    lines: [
      for (final line in j['lines'] as List)
        [
          for (final p in (line as Map<String, dynamic>)['pts'] as List)
            LatLng(
              ((p as List)[0] as num).toDouble(),
              (p[1] as num).toDouble(),
            ),
        ],
    ],
    arrows: [
      for (final a in j['arrows'] as List) RouteArrow.fromJson(a as List),
    ],
  );

  final List<List<LatLng>> lines;
  final List<RouteArrow> arrows;
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
