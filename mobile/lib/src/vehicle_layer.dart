/// The vehicles and the stops, painted over the basemap: one [CustomPaint] for
/// the whole city, driven by a ticker rather than by the socket. Route badges
/// are laid out once per route into a [ui.Paragraph] and reused, since laying
/// out text dominates the frame budget.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'here.dart';
import 'live.dart';
import 'map_theme.dart';
import 'models.dart';
import 'theme.dart';

/// Logical pixels.
const badgeRadius = 13.0;

/// Below this stops overlap into mush, so none are drawn.
const stopsZoom = 14.0;

const _stopRadius = 3.5;

/// Pixels between chevrons along a line. Measured on screen rather than on the
/// ground, so they stay this far apart at every zoom without being respaced.
const _arrowSpacing = 90.0;

/// Below this a chevron is a speck, so direction is skipped.
const _arrowZoom = 13.0;

/// Half the gap between the two tracks of chevrons on a two-way stretch.
const _twoWayOffset = 3.5;

class VehicleLayer extends StatefulWidget {
  const VehicleLayer({
    super.key,
    required this.catalog,
    required this.live,
    required this.stops,
    required this.selected,
    required this.theme,
    required this.here,
    required this.shapes,
    required this.lines,
    required this.arrowed,
  });

  final Catalog catalog;
  final Live live;

  final Shapes? shapes;

  /// Which routes get a line; [arrowed] alone gets direction arrows.
  final List<int> lines;
  final int? arrowed;

  final List<int> stops;
  final int? selected;
  final MapTheme theme;

  final Here here;

  @override
  State<VehicleLayer> createState() => _VehicleLayerState();
}

class _VehicleLayerState extends State<VehicleLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier(0);
  final Map<int, ui.Paragraph> _badges = {};

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _frame.value++)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  ui.Paragraph _badge(int route) => _badges.putIfAbsent(route, () {
    final label = routeNumber(widget.catalog.routes[route].short);
    final short = label.length > 4 ? label.substring(0, 4) : label;
    final size = short.length > 3 ? 9.0 : (short.length > 2 ? 11.0 : 13.0);
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: TextAlign.center,
              fontSize: size,
              fontWeight: FontWeight.w600,
            ),
          )
          ..pushStyle(ui.TextStyle(color: plate))
          ..addText(short);
    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: badgeRadius * 2));
  });

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _Painter(
          repaint: _frame,
          camera: camera,
          catalog: widget.catalog,
          live: widget.live,
          stops: widget.stops,
          selected: widget.selected,
          here: widget.here,
          shapes: widget.shapes,
          lines: widget.lines,
          arrowed: widget.arrowed,
          ink: Palette.of(widget.theme.dark),
          badge: _badge,
        ),
      ),
    );
  }
}

class _Painter extends CustomPainter {
  _Painter({
    required Listenable repaint,
    required this.camera,
    required this.catalog,
    required this.live,
    required this.stops,
    required this.selected,
    required this.here,
    required this.shapes,
    required this.lines,
    required this.arrowed,
    required this.ink,
    required this.badge,
  }) : super(repaint: repaint);

  final MapCamera camera;
  final Catalog catalog;
  final Live live;
  final List<int> stops;
  final int? selected;
  final Shapes? shapes;
  final List<int> lines;
  final int? arrowed;

  /// Read at paint time: a fix arriving between builds must still be drawn.
  final Here here;
  final Palette ink;
  final ui.Paragraph Function(int route) badge;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    // Under everything else: a line over a badge hides the number
    _paintLines(canvas, bounds);
    if (camera.zoom >= stopsZoom) _paintStops(canvas, bounds);
    _paintHere(canvas);
    _paintVehicles(canvas, bounds);
  }

  void _paintLines(Canvas canvas, Rect bounds) {
    final geometry = shapes;
    if (geometry == null) return;
    final casing = Paint()
      ..color = ink.edge.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (final i in lines) {
      if (i >= geometry.routes.length) continue;
      final route = catalog.routes[i];
      final path = ui.Path();
      for (final line in geometry.routes[i].lines) {
        var first = true;
        for (final p in line.pts) {
          final at = camera.latLngToScreenOffset(p);
          first ? path.moveTo(at.dx, at.dy) : path.lineTo(at.dx, at.dy);
          first = false;
        }
      }
      canvas.drawPath(path, casing);
      canvas.drawPath(
        path,
        Paint()
          ..color = routeColour(
            route.short,
            route.type,
          ).withValues(alpha: lines.length > 1 ? 0.75 : 1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    final one = arrowed;
    if (one == null || one >= geometry.routes.length) return;
    if (camera.zoom < _arrowZoom) return;
    final shape = geometry.routes[one];
    final ridge = Paint()
      ..color = ink.edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    for (final line in shape.lines) {
      // A route run both ways draws each direction as its own track of
      // chevrons, pushed to its own side, rather than two sharing one glyph
      final side = shape.twoWay
          ? (line.dir == 1 ? -_twoWayOffset : _twoWayOffset)
          : 0.0;
      _chevronsAlong(canvas, bounds, line.pts, side, ridge);
    }
  }

  /// Chevrons every `_arrowSpacing` pixels along one projected line, pointing
  /// the way it runs. Walking the line on screen rather than on the ground is
  /// what keeps the spacing even at every zoom, and lets a stretch off screen
  /// be skipped a point at a time.
  void _chevronsAlong(
    Canvas canvas,
    Rect bounds,
    List<LatLng> pts,
    double side,
    Paint paint,
  ) {
    final room = bounds.inflate(24);
    var at = camera.latLngToScreenOffset(pts.first);
    var run = _arrowSpacing / 2;
    for (var k = 1; k < pts.length; k++) {
      final next = camera.latLngToScreenOffset(pts[k]);
      final step = next - at;
      final length = step.distance;
      if (length > 0) {
        final cos = step.dx / length;
        final sin = step.dy / length;
        for (run += length; run >= _arrowSpacing; run -= _arrowSpacing) {
          final on = next - Offset(cos, sin) * (run - _arrowSpacing);
          final push = Offset(-sin * side, cos * side);
          if (room.contains(on)) _chevron(canvas, on + push, cos, sin, paint);
        }
      }
      at = next;
    }
  }

  /// One chevron on the line, its point along `(cos, sin)` and its arms
  /// trailing behind, in the page's ink so it reads as a notch on the line.
  void _chevron(Canvas canvas, Offset at, double cos, double sin, Paint paint) {
    const reach = 4.0;
    const wide = 4.0;
    canvas.drawPath(
      ui.Path()
        ..moveTo(
          at.dx - cos * reach - sin * wide,
          at.dy - sin * reach + cos * wide,
        )
        ..lineTo(at.dx + cos * reach, at.dy + sin * reach)
        ..lineTo(
          at.dx - cos * reach + sin * wide,
          at.dy - sin * reach - cos * wide,
        ),
      paint,
    );
  }

  void _paintHere(Canvas canvas) {
    final fix = here.fix;
    if (fix == null) return;
    final at = camera.latLngToScreenOffset(fix.point);
    // The accuracy ring is measured by projecting a point that far north, so
    // it follows the zoom without arithmetic of its own
    final north = camera.latLngToScreenOffset(
      LatLng(fix.point.latitude + fix.accuracy / 111320, fix.point.longitude),
    );
    final ring = (at - north).distance;
    if (ring > _stopRadius * 2) {
      canvas.drawCircle(
        at,
        ring,
        Paint()..color = ink.here.withValues(alpha: 0.12),
      );
    }
    // The halo keeps the dot findable when the ring is too small to draw
    canvas.drawCircle(
      at,
      15,
      Paint()..color = ink.here.withValues(alpha: 0.22),
    );
    canvas.drawCircle(
      at,
      15,
      Paint()
        ..color = ink.here.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawCircle(
      at,
      9,
      Paint()
        ..color = ink.edge
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(at, 8, Paint()..color = ink.edge);
    canvas.drawCircle(at, 6, Paint()..color = ink.here);
  }

  void _paintStops(Canvas canvas, Rect bounds) {
    final fill = Paint()..color = ink.stop;
    final edge = Paint()
      ..color = ink.edge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final i in stops) {
      final s = catalog.stops[i];
      final at = camera.latLngToScreenOffset(LatLng(s.lat, s.lon));
      if (!bounds.inflate(_stopRadius).contains(at)) continue;
      canvas.drawCircle(at, _stopRadius, fill);
      canvas.drawCircle(at, _stopRadius, edge);
      if (i == selected) {
        canvas.drawCircle(
          at,
          _stopRadius + 5,
          Paint()
            ..color = ink.nub
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  void _paintVehicles(Canvas canvas, Rect bounds) {
    final now = live.nowMs;
    final margin = bounds.inflate(badgeRadius + 8);
    final edge = Paint()
      ..color = const Color(0xd908090e)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final nub = Paint()..color = ink.nub;
    final standing = Paint()
      ..color = ink.nub
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;
    final faded = ink.nub.withValues(alpha: 0.55);
    for (final v in live.vehicles.values) {
      final at = sample(v, now);
      final p = camera.latLngToScreenOffset(LatLng(at.lat, at.lon));
      if (!margin.contains(p)) continue;

      final route = catalog.routes[v.route];
      final fill = Paint()..color = routeColour(route.short, route.type);
      // Faded: nothing has confirmed this position for half a minute
      if (v.stale) {
        fill.color = fill.color.withValues(alpha: 0.55);
      }
      nub.color = standing.color = v.stale ? faded : ink.nub;
      canvas.drawCircle(p, badgeRadius - 1.5, fill);
      canvas.drawCircle(p, badgeRadius - 1.5, edge);

      // The wedge sits on the rim so the number stays readable. Solid means
      // under way, an outline means standing
      final a = (at.heading - 90 + camera.rotation) * math.pi / 180;
      final cos = math.cos(a);
      final sin = math.sin(a);
      canvas.drawPath(
        ui.Path()
          ..moveTo(
            p.dx + cos * (badgeRadius + 5),
            p.dy + sin * (badgeRadius + 5),
          )
          ..lineTo(
            p.dx + cos * badgeRadius - sin * 5,
            p.dy + sin * badgeRadius + cos * 5,
          )
          ..lineTo(
            p.dx + cos * badgeRadius + sin * 5,
            p.dy + sin * badgeRadius - cos * 5,
          )
          ..close(),
        v.moving ? nub : standing,
      );

      final text = badge(v.route);
      canvas.drawParagraph(text, p - Offset(badgeRadius, text.height / 2));
    }
  }

  @override
  bool shouldRepaint(_Painter old) => true;
}
