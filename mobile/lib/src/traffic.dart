/// How fast the streets are running, for as long as the view is open. The
/// stretches themselves never change, so they are fetched once and kept across
/// openings; the numbers are small, and are asked for again every minute while
/// the view is up and not at all while it is down.
///
/// There are about 27,000 stretches, which is too many to hand the map as
/// polylines: each one costs its own culling and its own stroked path every
/// frame. Instead they are projected once, at [_zoom], into the plane the map
/// itself draws in, and gathered into one path per colour. A frame is then a
/// couple of dozen `drawPath` calls under one transform, and panning or zooming
/// re-projects nothing at all.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter_map/flutter_map.dart';

import 'api.dart';
import 'models.dart';

const trafficPeriod = Duration(seconds: 60);

/// The zoom the stretches are projected at. Web Mercator pixels scale by a power
/// of two between zooms, so one projection serves every zoom under a scale.
const _zoom = 18.0;

/// Colour steps between [_low] and [_high]. A stretch is drawn in the nearest
/// one, which is what lets tens of thousands of them share a handful of paths;
/// the ramp moves far less than an eye can see over one step.
const _bands = 20;
const _low = 0.7;
const _high = 1.7;

const _width = 4.0;

/// The ramp: actual over timetabled travel time, and the colour for it. 1 is
/// exactly the timetable, so green is ahead of it and red is a crawl.
const trafficRamp = <(double, Color)>[
  (0.85, Color(0xff22c55e)),
  (1.0, Color(0xffa3e635)),
  (1.15, Color(0xfffacc15)),
  (1.3, Color(0xfffb923c)),
  (1.6, Color(0xffef4444)),
];

/// Null where too little has been seen to say, which is drawn as nothing.
Color? trafficColour(double? ratio) {
  if (ratio == null) return null;
  var (was, colour) = trafficRamp.first;
  if (ratio <= was) return colour;
  for (final (upto, next) in trafficRamp.skip(1)) {
    if (ratio <= upto) {
      return Color.lerp(colour, next, (ratio - was) / (upto - was));
    }
    was = upto;
    colour = next;
  }
  return colour;
}

const _crs = Epsg3857();

/// Held across openings of the view, and across a rebuild of the layer: where
/// the stretches land in the map's own plane. The server they came from is kept
/// with them, since another one measures other stretches.
({String base, List<List<Offset>> lines})? _held;

List<List<Offset>> _project(Streets streets) => [
  for (final line in streets.lines)
    [for (final p in line) _crs.latLngToOffset(p, _zoom)],
];

/// One colour's worth of stretches, in the projected plane.
typedef _Band = ({Path path, Color colour});

List<_Band> _bandsOf(List<List<Offset>> lines, Traffic now) {
  final paths = List.generate(_bands, (_) => Path(), growable: false);
  final used = List.filled(_bands, false);
  final step = (_high - _low) / (_bands - 1);
  for (var i = 0; i < lines.length && i < now.ratio.length; i++) {
    final r = now.ratio[i];
    final pts = lines[i];
    if (r == null || pts.length < 2) continue;
    final band = ((r - _low) / step).round().clamp(0, _bands - 1);
    used[band] = true;
    final path = paths[band];
    path.moveTo(pts.first.dx, pts.first.dy);
    for (var k = 1; k < pts.length; k++) {
      path.lineTo(pts[k].dx, pts[k].dy);
    }
  }
  return [
    for (var band = 0; band < _bands; band++)
      if (used[band])
        (
          path: paths[band],
          colour: trafficColour(_low + band * step)!.withValues(alpha: 0.85),
        ),
  ];
}

class TrafficLayer extends StatefulWidget {
  const TrafficLayer({super.key, required this.api});

  final Api api;

  @override
  State<TrafficLayer> createState() => _TrafficLayerState();
}

class _TrafficLayerState extends State<TrafficLayer> {
  List<_Band>? _drawn;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(trafficPeriod, (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (_held?.base != widget.api.base) {
        _held = (
          base: widget.api.base,
          lines: _project(await widget.api.streets()),
        );
      }
    } on Exception {
      // Nothing to colour, so the view is simply the map it sits on
      return;
    }
    await _ask();
  }

  Future<void> _ask() async {
    try {
      // Built here rather than in `build`, which runs on every pan and frame
      final drawn = _bandsOf(_held!.lines, await widget.api.traffic());
      if (mounted) setState(() => _drawn = drawn);
    } on Exception {
      // The last numbers stay up rather than the view emptying for a minute
    }
  }

  @override
  Widget build(BuildContext context) {
    final drawn = _drawn;
    if (drawn == null) return const SizedBox.shrink();
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _Painter(camera: MapCamera.of(context), bands: drawn),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  const _Painter({required this.camera, required this.bands});

  final MapCamera camera;
  final List<_Band> bands;

  @override
  void paint(Canvas canvas, Size size) {
    // The whole overlay under one transform - the same one the map applies to a
    // projected point - so nothing is rebuilt when the camera moves
    final scale = math.pow(2.0, camera.zoom - _zoom).toDouble();
    final origin = _crs.latLngToOffset(camera.center, _zoom);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(camera.rotationRad);
    canvas.scale(scale);
    canvas.translate(-origin.dx, -origin.dy);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      // Scaled back out, so a stretch is the same width at every zoom
      ..strokeWidth = _width / scale
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (final band in bands) {
      canvas.drawPath(band.path, paint..color = band.colour);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Painter old) =>
      old.bands != bands ||
      old.camera.zoom != camera.zoom ||
      old.camera.center != camera.center ||
      old.camera.rotation != camera.rotation;
}
