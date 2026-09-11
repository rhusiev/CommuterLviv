/// One arrival, said the way a person waiting would say it.
library;

import 'package:flutter/material.dart';

import 'eta.dart';
import 'models.dart';
import 'route_badge.dart';

/// A route badge and how long until it calls.
class Due extends StatelessWidget {
  const Due({
    super.key,
    required this.route,
    required this.arrival,
    this.onLine,
  });

  final TransitRoute route;
  final Arrival arrival;

  final VoidCallback? onLine;

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
    // ActionChip rather than a Chip in an InkWell: the wrapper's ink paints a
    // rectangle the size of the chip's margins and spills past the stadium
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
