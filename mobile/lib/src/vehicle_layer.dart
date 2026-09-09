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

import 'live.dart';
import 'map_theme.dart';
import 'models.dart';

/// Badge radius, in logical pixels
const badgeRadius = 13.0;

/// Below this the city is a mess of overlapping circles and no stop is worth
/// tapping, so none are drawn
const stopsZoom = 14.0;

const _stopRadius = 3.5;

class VehicleLayer extends StatefulWidget {
  const VehicleLayer({
    super.key,
    required this.catalog,
    required this.live,
    required this.stops,
    required this.selected,
    required this.theme,
  });

  final Catalog catalog;
  final Live live;

  /// Indexes of the stops worth drawing: the ones the chosen routes call at
  final List<int> stops;
  final int? selected;
  final MapTheme theme;

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
    final label = widget.catalog.routes[route].short;
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
          ..pushStyle(ui.TextStyle(color: const Color(0xff0b0f14)))
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
    required this.ink,
    required this.badge,
  }) : super(repaint: repaint);

  final MapCamera camera;
  final Catalog catalog;
  final Live live;
  final List<int> stops;
  final int? selected;
  final Palette ink;
  final ui.Paragraph Function(int route) badge;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    if (camera.zoom >= stopsZoom) _paintStops(canvas, bounds);
    _paintVehicles(canvas, bounds);
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
