/// The vehicles and the stops, painted over the basemap.
///
/// One [CustomPaint] for the whole city, driven by a ticker rather than by the
/// socket: positions arrive every five seconds and are eased between, so the
/// layer repaints at the display's rate whatever the network is doing. Nothing
/// here is a widget - four hundred widgets rebuilt sixty times a second is the
/// one thing that would not fit in a frame.
///
/// Route badges are laid out once per route into a [ui.Paragraph] and drawn
/// thereafter. Laying out text is orders of magnitude dearer than drawing an
/// already-laid-out one, and that cost is where a map like this would otherwise
/// spend its whole budget.
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

/// Badge radius, in logical pixels
const badgeRadius = 13.0;

/// Below this the city is a mess of overlapping circles and no stop is worth
/// tapping, so none are drawn
const stopsZoom = 14.0;

const _stopRadius = 3.5;

/// What `live/geometry.py` used, in metres: the arrows arrive that far apart
const _arrowSpacing = 220.0;

/// Below this the whole route is on screen and an arrowhead is a speck of
/// speckle on the line. The line alone says where the route runs; the zoom that
/// shows a street is the one where which way it runs is a question
const _arrowZoom = 13.0;

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

  /// Every route's geometry, once something has asked for it
  final Shapes? shapes;

  /// Which routes to draw a line for, and which one - if any - carries the
  /// direction arrows. Arrows are for the single route being looked at; a
  /// city's worth of them would be a texture, not information
  final List<int> lines;
  final int? arrowed;

  /// Indexes of the stops worth drawing: the ones the chosen routes call at
  final List<int> stops;
  final int? selected;
  final MapTheme theme;

  /// Where the phone is, when it has been asked and told
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

  /// Read at paint time, not at build time: the ticker repaints every frame,
  /// and a fix that arrived between builds has to be on the next one
  final Here here;
  final Palette ink;
  final ui.Paragraph Function(int route) badge;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    // Under everything else: a route is the background a rider reads the
    // vehicles against, and a line over a badge hides the number
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
        for (final p in line) {
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
    final arrows = geometry.routes[one].arrows;
    // The server spaces arrows every 220 m along the line, which at the zoom
    // that holds a whole route is five pixels: drawn as they come the line
    // reads as a dashed one. They arrive in order along each shape, so every
    // nth is still evenly spaced - just further apart
    // Web mercator, at the camera's own latitude: 80 px of screen is this
    // many metres of street
    final metres =
        80 *
        156543.03392 *
        math.cos(camera.center.latitude * math.pi / 180) /
        math.pow(2, camera.zoom);
    final step = math.max(1, (metres / _arrowSpacing).ceil());
    final head = Paint()..color = ink.edge;
    for (var k = 0; k < arrows.length; k += step) {
      final arrow = arrows[k];
      final at = camera.latLngToScreenOffset(arrow.at);
      if (!bounds.inflate(12).contains(at)) continue;
      final a = (arrow.heading - 90 + camera.rotation) * math.pi / 180;
      final cos = math.cos(a);
      final sin = math.sin(a);
      // Two heads back to back would sit on top of each other and read as a
      // diamond, so each backs off along the line by its own length
      final off = arrow.twoWay ? 9.0 : 0.0;
      _head(canvas, at + Offset(cos * off, sin * off), cos, sin, head);
      if (arrow.twoWay) {
        _head(canvas, at - Offset(cos * off, sin * off), -cos, -sin, head);
      }
    }
  }

  /// One arrowhead sitting on the line, pointing along `(cos, sin)`. Drawn in
  /// the page's ink rather than the route's colour: it is a notch cut out of
  /// the line, and a coloured head on a line of that colour is nothing at all.
  void _head(Canvas canvas, Offset at, double cos, double sin, Paint paint) {
    canvas.drawPath(
      ui.Path()
        ..moveTo(at.dx + cos * 7, at.dy + sin * 7)
        ..lineTo(at.dx - cos * 3 - sin * 4.5, at.dy - sin * 3 + cos * 4.5)
        ..lineTo(at.dx - cos * 3 + sin * 4.5, at.dy - sin * 3 - cos * 4.5)
        ..close(),
      paint,
    );
  }

  void _paintHere(Canvas canvas) {
    final fix = here.fix;
    if (fix == null) return;
    final at = camera.latLngToScreenOffset(fix.point);
    // The ring is the honest part of this: a 300 m fix indoors drawn as a 6 px
    // dot claims a precision the phone never had. It is measured by projecting
    // a point that far north, so it follows the zoom without arithmetic of its
    // own
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
    // A 6 px dot is the same mark as a stop and loses to forty vehicles around
    // it. The halo is what makes it findable without panning: a soft disc that
    // is there at every zoom, even when the accuracy ring is too small to draw
    canvas.drawCircle(at, 15, Paint()..color = ink.here.withValues(alpha: 0.22));
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
      // A stale marker is a position nobody has confirmed for half a minute,
      // and saying so costs one number of opacity
      if (v.stale) {
        fill.color = fill.color.withValues(alpha: 0.55);
      }
      nub.color = standing.color = v.stale ? faded : ink.nub;
      canvas.drawCircle(p, badgeRadius - 1.5, fill);
      canvas.drawCircle(p, badgeRadius - 1.5, edge);

      // The direction wedge sits on the rim rather than inside it, so the
      // number stays readable at any angle. It is drawn whether or not the
      // vehicle is moving - which way it faces is known either way, and a
      // marker with no wedge left no way to tell one end of the route from the
      // other. Solid means under way; an outline means standing, so the wedge
      // says where it will go without claiming it is going there now
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
