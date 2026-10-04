/// The camera keeping to the dot while a journey is followed. A hand on the map
/// lets go of it, so the way ahead can be looked at; the locate button takes it
/// back.
library;

import 'dart:async';

import 'package:flutter_map/flutter_map.dart';

import 'here.dart';

/// What moves the camera without a hand on the map.
const _notByHand = {
  MapEventSource.mapController,
  MapEventSource.fitCamera,
  MapEventSource.custom,
  MapEventSource.nonRotatedSizeChange,
  MapEventSource.interactiveFlagsChanged,
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
    if (event is MapEventMove && !_notByHand.contains(event.source)) {
      _held = false;
    }
  }

  void _centre() {
    final at = here.fix?.point;
    if (_held && at != null) map.move(at, map.camera.zoom);
  }
}
