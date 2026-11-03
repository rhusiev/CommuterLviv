/// The camera keeping to the dot while a journey is followed. Panning the map
/// lets go of it, so the way ahead can be looked at; the locate button takes it
/// back.
library;

import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'here.dart';
import 'live.dart';

/// A pan by hand. A zoom - a pinch, a double tap, the buttons - keeps the dot
/// in the middle, as navigation apps do.
const _pans = {
  MapEventSource.dragStart,
  MapEventSource.onDrag,
  MapEventSource.dragEnd,
  MapEventSource.flingAnimationController,
};

class Tracking {
  Tracking(this.map, this.here);

  final MapController map;
  final Here here;

  StreamSubscription<MapEvent>? _events;
  bool _held = false;

  /// Whether the camera is on the dot and goes with each fix.
  bool get held => _held;

  /// Takes the camera to the dot, now if there is a fix and with every one
  /// after.
  void start() {
    if (_events == null) {
      _events = map.mapEventStream.listen(_moved);
      here.addListener(_centre);
    }
    _held = true;
    _centre();
  }

  void stop() {
    _events?.cancel();
    _events = null;
    here.removeListener(_centre);
    _held = false;
  }

  void _moved(MapEvent event) {
    if (event is MapEventMove && _pans.contains(event.source)) {
      _held = false;
    }
  }

  void _centre() {
    final at = here.fix?.point;
    if (_held && at != null) map.move(at, map.camera.zoom);
  }
}

/// How often the camera catches up with a followed vehicle: it moves between
/// reports, eased, so a few steps a second are smooth enough to read.
const _vehicleStep = Duration(milliseconds: 100);

/// The camera keeping to one vehicle, from its card, until a pan lets go of it
/// or [stop] is called.
class VehicleTracking {
  VehicleTracking(this.map, this.live);

  final MapController map;

  /// Read each step: a renewed city brings a new one
  final Live? Function() live;

  StreamSubscription<MapEvent>? _events;
  Timer? _steps;
  int? _veh;

  /// The wire id of the vehicle followed, null while none is.
  int? get veh => _veh;

  void start(int veh) {
    stop();
    _veh = veh;
    _events = map.mapEventStream.listen((event) {
      if (event is MapEventMove && _pans.contains(event.source)) stop();
    });
    _steps = Timer.periodic(_vehicleStep, (_) => _centre());
    _centre();
  }

  void stop() {
    _events?.cancel();
    _events = null;
    _steps?.cancel();
    _steps = null;
    _veh = null;
  }

  void _centre() {
    final now = live();
    final v = now?.vehicles[_veh];
    if (now == null || v == null) return;
    final at = sample(v, now.nowMs);
    final to = LatLng(at.lat, at.lon);
    if (to != map.camera.center) map.move(to, map.camera.zoom);
  }
}
