/// One arrival, said the way a person waiting would say it.
library;

import 'package:flutter/material.dart';

import 'eta.dart';
import 'models.dart';
import 'route_badge.dart';

/// A route badge and how long until it calls. Half a minute away reads "now",
/// because "0 min" invites the reader to think it is late rather than here.
class Due extends StatelessWidget {
  const Due({
    super.key,
    required this.route,
    required this.arrival,
    this.onLine,
  });

  final TransitRoute route;
  final Arrival arrival;

  /// Where the line lives, when whoever placed this has somewhere to put it.
  /// Nothing else on this chip is tappable, so the whole chip is the target
  final VoidCallback? onLine;

  // The badge is the label rather than the avatar: an avatar is a circle sized
  // for one glyph, and this one is a glyph and a number
  @override
  Widget build(BuildContext context) {
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RouteBadge(route: route, fontSize: 10),
        const SizedBox(width: 6),
        Text(countdown(arrival.t)),
      ],
    );
    // ActionChip rather than a Chip under an InkWell: the ink of a wrapper is
    // a rectangle the size of the chip's own margins, which on a press spills
    // out past the stadium it is meant to fill
    if (onLine == null) {
      return Chip(visualDensity: VisualDensity.compact, label: label);
    }
    return ActionChip(
      visualDensity: VisualDensity.compact,
      label: label,
      onPressed: onLine,
    );
  }
}
