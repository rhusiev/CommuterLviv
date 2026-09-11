/// A route, wherever one is named: a kind glyph, then its number. The glyphs
/// are drawn here in a 24-unit box because Material has no trolleybus.
library;

import 'package:flutter/material.dart';

import 'map_theme.dart';
import 'models.dart';
import 'theme.dart';

class ModeIcon extends StatelessWidget {
  const ModeIcon({super.key, required this.type, this.size = 16, this.colour});

  final String type;
  final double size;
  final Color? colour;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _Mode(type, colour ?? IconTheme.of(context).color ?? plate),
  );
}

class _Mode extends CustomPainter {
  const _Mode(this.type, this.colour);

  final String type;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 24;
    final tram = type == 'tram';
    final pen = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * u
      ..strokeCap = StrokeCap.round;
    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1 * u, y1 * u), Offset(x2 * u, y2 * u), pen);

    final left = tram ? 6.5 : 4.5;
    final right = tram ? 17.5 : 19.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(left * u, 4.5 * u, right * u, 17.5 * u),
        Radius.circular(3 * u),
      ),
      pen,
    );
    line(left, 11, right, 11);
    line(tram ? 9 : 8, 17.5, tram ? 9 : 8, 20);
    line(tram ? 15 : 16, 17.5, tram ? 15 : 16, 20);
    if (tram) {
      line(12, 4.5, 12, 2);
      line(8, 2, 16, 2);
    }
    if (type == 'trolleybus') {
      line(14, 4.5, 18.5, 1);
      line(11, 4.5, 15.5, 1);
    }
  }

  @override
  bool shouldRepaint(_Mode old) => old.type != type || old.colour != colour;
}

/// [muted] draws the shape without the route's colour.
class RouteBadge extends StatelessWidget {
  const RouteBadge({
    super.key,
    required this.route,
    this.muted = false,
    this.fontSize = 12,
  });

  final TransitRoute route;
  final bool muted;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final ink = muted ? Theme.of(context).colorScheme.onSurfaceVariant : plate;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: muted ? null : routeColour(route.short, route.type),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ModeIcon(type: route.type, size: fontSize + 4, colour: ink),
          const SizedBox(width: 4),
          // A floor of two digits, so a wall of chips lines up
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: fontSize * 1.4),
            child: Text(
              routeNumber(route.short),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
