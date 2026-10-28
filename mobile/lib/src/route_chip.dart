/// A route, the same chip wherever one is shown.
library;

import 'package:flutter/material.dart';

import 'models.dart';
import 'route_badge.dart';
import 'strings.dart';
import 'theme.dart';

/// How tall the chip is drawn; its row is [kMinInteractiveDimension], as a
/// Material chip's is.
const _height = 36.0;
const _lineWidth = 32.0;

/// The gap between the two targets, and how round their inner corners are: a
/// split button, so each press lights the whole of what it presses.
const _split = 2.0;
const _inner = Radius.circular(4);
const _outer = Radius.circular(_height / 2);
const _bodyShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.horizontal(left: _outer, right: _inner),
);
const _lineShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.horizontal(left: _inner, right: _outer),
);

/// The body watches [route] on the map or stops watching it, and the `›`
/// beside it opens the route's line. Both are drawn as targets of their own,
/// so nothing hides behind a long press. [trailing] follows the badge in the body, such
/// as a countdown. With a [width] the body takes what the `›` leaves; without
/// one the chip is as wide as what it holds, so a row of them flows.
class RouteChip extends StatelessWidget {
  const RouteChip({
    super.key,
    required this.route,
    required this.watched,
    required this.onWatch,
    required this.onLine,
    this.trailing,
    this.width,
    this.fontSize = 12,
  });

  final TransitRoute route;
  final bool watched;
  final VoidCallback onWatch;
  final VoidCallback onLine;
  final Widget? trailing;
  final double? width;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final body = Semantics(
      button: true,
      toggled: watched,
      hint: watched ? txt.unwatchRoute : txt.watchRoute,
      child: InkWell(
        onTap: onWatch,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              RouteBadge(route: route, muted: !watched, fontSize: fontSize),
              if (trailing != null) ...[const SizedBox(width: 6), trailing!],
            ],
          ),
        ),
      ),
    );
    final line = Semantics(
      button: true,
      label: txt.lineOf(route.short),
      excludeSemantics: true,
      child: InkWell(
        onTap: onLine,
        child: const SizedBox(
          width: _lineWidth,
          child: Icon(Icons.chevron_right, size: 18),
        ),
      ),
    );
    return SizedBox(
      width: width,
      height: kMinInteractiveDimension,
      child: Center(
        widthFactor: 1,
        child: SizedBox(
          height: _height,
          child: Row(
            mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
            children: [
              if (width == null)
                _Segment(shape: _bodyShape, child: body)
              else
                Expanded(
                  child: _Segment(shape: _bodyShape, child: body),
                ),
              const SizedBox(width: _split),
              _Segment(shape: _lineShape, child: line),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the chip's two targets, drawn as a whole: a press lights all of it.
class _Segment extends StatelessWidget {
  const _Segment({required this.shape, required this.child});

  final ShapeBorder shape;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: raised,
    shape: shape,
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}
