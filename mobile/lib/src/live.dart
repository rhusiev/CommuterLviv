/// Everything arriving over the socket, and the current position of every
/// vehicle on it.
///
/// Positions live here rather than in widget state on purpose: four hundred
/// vehicles moving sixty times a second is a repaint of one custom painter, not
/// a rebuild of a tree. Widgets listen to [changes] for the things that change
/// rarely - the connection, the arrivals, the vehicle count - and the painter
/// reads [vehicles] directly on every tick.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';

import 'api.dart';
import 'models.dart';
import 'wire.dart' as wire;

/// How long a vehicle takes to slide from where it was drawn to where the
/// server says it is. Positions arrive every five seconds; easing over a little
/// over a second reads as movement without lagging visibly behind the truth.
const _ease = Duration(milliseconds: 1200);

enum Connection { connecting, live, offline }

class Vehicle {
  Vehicle({
    required this.route,
    required this.flags,
    required this.lat0,
    required this.lon0,
    required this.lat1,
    required this.lon1,
    required this.h0,
    required this.h1,
    required this.t0,
  });

  int route;
  int flags;
  double lat0, lon0, lat1, lon1, h0, h1;
  int t0;

  bool get moving => flags & wire.movingFlag != 0;
  bool get stale => flags & wire.staleFlag != 0;
}

/// Where a vehicle is right now, between the last two things the server said.
/// Heading takes the short way round, so a bus turning past north does not spin
/// three hundred degrees the wrong way.
({double lat, double lon, double heading}) sample(Vehicle v, int nowMs) {
  final k = ((nowMs - v.t0) / _ease.inMilliseconds).clamp(0.0, 1.0);
  final e = k * (2 - k); // ease-out: fastest on arrival, settling into place
  final dh = ((v.h1 - v.h0 + 540) % 360) - 180;
  return (
    lat: v.lat0 + (v.lat1 - v.lat0) * e,
    lon: v.lon0 + (v.lon1 - v.lon0) * e,
    heading: v.h0 + dh * e,
  );
}

class Live extends ChangeNotifier {
  Live(this._api);

  final Api _api;
  final Map<int, Vehicle> vehicles = {};

  Map<int, List<Arrival>> arrivals = {};
  double arrivalsAt = 0;
  Connection connection = Connection.connecting;

  IOWebSocketChannel? _ws;
  StreamSubscription<dynamic>? _sub;
  List<int> _routes = const [];
  List<int> _stops = const [];
  Duration _backoff = const Duration(milliseconds: 500);
  Timer? _retry;
  bool _closed = false;
  final Stopwatch _clock = Stopwatch()..start();

  /// The painter's clock. `DateTime.now()` would do, but a stopwatch cannot
  /// jump when the phone's clock is corrected mid-animation.
  int get nowMs => _clock.elapsedMilliseconds;

  void open() {
    _closed = false;
    _connect();
  }

  @override
  void dispose() {
    _closed = true;
    _retry?.cancel();
    _sub?.cancel();
    _ws?.sink.close();
    super.dispose();
  }

  void setRoutes(List<int> routes) {
    _routes = routes;
    vehicles.clear();
    _send({'type': 'routes', 'routes': routes});
    notifyListeners();
  }

  void setStops(List<int> stops) {
    _stops = stops;
    _send({'type': 'stops', 'stops': stops});
  }

  void _send(Object msg) => _ws?.sink.add(jsonEncode(msg));

  Future<void> _connect() async {
    if (_closed) return;
    try {
      final socket = await WebSocket.connect(
        _api.socketUri().toString(),
        headers: _api.socketHeaders,
      );
      if (_closed) {
        await socket.close();
        return;
      }
      final ws = IOWebSocketChannel(socket);
      _ws = ws;
      _backoff = const Duration(milliseconds: 500);
      connection = Connection.live;
      _send({'type': 'routes', 'routes': _routes});
      if (_stops.isNotEmpty) _send({'type': 'stops', 'stops': _stops});
      notifyListeners();
      _sub = ws.stream.listen(
        _message,
        onDone: () => _dropped(ws),
        onError: (_) => _dropped(ws),
        cancelOnError: true,
      );
    } catch (_) {
      _dropped(null);
    }
  }

  void _dropped(IOWebSocketChannel? which) {
    if (which != null && _ws != which) return;
    _ws = null;
    _sub?.cancel();
    _sub = null;
    connection = _closed ? Connection.offline : Connection.connecting;
    notifyListeners();
    if (_closed) return;
    _retry = Timer(_backoff, _connect);
    final next = _backoff * 2;
    _backoff = next > const Duration(seconds: 15)
        ? const Duration(seconds: 15)
        : next;
  }

  void _message(dynamic data) {
    if (data is String) {
      _text(data);
    } else if (data is List<int>) {
      _frame(data is Uint8List ? data : Uint8List.fromList(data));
    }
  }

  void _text(String raw) {
    final Object? msg;
    try {
      msg = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (msg is! Map || msg['type'] != 'arrivals') return;
    arrivals = {
      for (final e in (msg['stops'] as Map<String, dynamic>).entries)
        int.parse(e.key): [
          for (final a in e.value as List)
            Arrival.fromJson(a as Map<String, dynamic>),
        ],
    };
    arrivalsAt = (msg['t'] as num).toDouble();
    notifyListeners();
  }

  void _frame(Uint8List buf) {
    final wire.Frame f;
    try {
      f = wire.decode(buf);
    } on FormatException {
      return;
    }
    final now = nowMs;
    if (f.kind == wire.snapshot) vehicles.clear();
    for (var i = 0; i < f.n; i++) {
      final had = vehicles[f.ids[i]];
      if (had == null) {
        vehicles[f.ids[i]] = Vehicle(
          route: f.routes[i],
          flags: f.flags[i],
          lat0: f.lats[i],
          lon0: f.lons[i],
          lat1: f.lats[i],
          lon1: f.lons[i],
          h0: f.headings[i],
          h1: f.headings[i],
          t0: now,
        );
      } else {
        final at = sample(had, now);
        had
          ..lat0 = at.lat
          ..lon0 = at.lon
          ..h0 = at.heading
          ..lat1 = f.lats[i]
          ..lon1 = f.lons[i]
          ..h1 = f.headings[i]
          ..t0 = now
          ..route = f.routes[i]
          ..flags = f.flags[i];
      }
    }
    if (f.kind == wire.delta) {
      for (final id in f.gone) {
        vehicles.remove(id);
      }
    }
    // A delta that only moved vehicles changes nothing a widget shows: the
    // count is the same and the painter is already repainting every frame
    if (f.kind == wire.snapshot || f.gone.isNotEmpty) notifyListeners();
  }
}
