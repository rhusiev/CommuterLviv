/// Zoom, a compass that appears once the map is off north, and the gesture
/// settings those share limits with.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import 'here.dart';
import 'strings.dart';
import 'theme.dart';

/// The city fits one screen at 9; the basemap says nothing more past 18.
const minZoom = 9.0;
const maxZoom = 18.0;

/// The thresholds below only apply with the gesture race on: without it every
/// gesture runs at once and a pinch's incidental twist turns the map.
const mapInteraction = InteractionOptions(
  enableMultiFingerGestureRace: true,
  rotationThreshold: 12, // degrees
  pinchZoomThreshold: 0.35, // zoom levels
  // A won rotation must not lock zooming out for the rest of the touch, as the
  // package's default would
  rotationWinGestures: MultiFingerGesture.all,
);

class MapControls extends StatefulWidget {
  const MapControls({super.key, required this.map, required this.here});

  final MapController map;

  final Here here;

  @override
  State<MapControls> createState() => _MapControlsState();
}

class _MapControlsState extends State<MapControls> {
  StreamSubscription<MapEvent>? _events;

  @override
  void initState() {
    super.initState();
    // The buttons read the camera, so a gesture has to rebuild them too
    _events = widget.map.mapEventStream.listen((_) {
      if (mounted) setState(() {});
    });
    widget.here.addListener(_redraw);
  }

  @override
  void dispose() {
    _events?.cancel();
    widget.here.removeListener(_redraw);
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  Future<void> _locate() async {
    final at = await widget.here.start();
    if (at != null && mounted) widget.map.move(at, 16);
  }

  void _zoom(double by) {
    final camera = widget.map.camera;
    final to = (camera.zoom + by).clamp(minZoom, maxZoom);
    if (to != camera.zoom) widget.map.move(camera.center, to);
  }

  @override
  Widget build(BuildContext context) {
    final camera = widget.map.camera;
    final locating = widget.here.state;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MapButton(
          tooltip: locating == Locating.denied ? txt.noLocation : txt.whereAmI,
          onPressed: locating == Locating.denied ? null : _locate,
          child: Icon(
            locating == Locating.on
                ? Icons.my_location
                : Icons.location_searching,
            color: locating == Locating.on
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
        ),
        if (camera.rotation != 0)
          _MapButton(
            tooltip: txt.faceNorth,
            onPressed: () => widget.map.rotate(0),
            // Counter-rotate with the camera to keep pointing at north
            child: Transform.rotate(
              angle: camera.rotationRad,
              child: const Icon(Icons.navigation_outlined),
            ),
          ),
        _MapButton(
          tooltip: txt.zoomIn,
          onPressed: camera.zoom < maxZoom ? () => _zoom(1) : null,
          child: const Icon(Icons.add),
        ),
        _MapButton(
          tooltip: txt.zoomOut,
          onPressed: camera.zoom > minZoom ? () => _zoom(-1) : null,
          child: const Icon(Icons.remove),
        ),
      ],
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: RoundButton(tooltip: tooltip, onPressed: onPressed, child: child),
  );
}
