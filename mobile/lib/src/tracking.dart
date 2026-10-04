/// The camera keeping to the dot while a journey is followed. Panning the map
/// lets go of it, so the way ahead can be looked at; the locate button takes it
/// back.
library;

import 'dart:async';

import 'package:flutter_map/flutter_map.dart';

import 'here.dart';

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
