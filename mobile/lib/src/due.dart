/// One arrival, said the way a person waiting would say it.
library;

import 'package:flutter/material.dart';

import 'eta.dart';
import 'models.dart';
import 'route_chip.dart';

/// A route's chip with how long until it calls.
class Due extends StatelessWidget {
  const Due({
    super.key,
    required this.route,
    required this.arrival,
    required this.watched,
    required this.onWatch,
    required this.onLine,
  });

  final TransitRoute route;
  final Arrival arrival;
  final bool watched;
  final VoidCallback onWatch;
  final VoidCallback onLine;

  @override
  Widget build(BuildContext context) => RouteChip(
    route: route,
    watched: watched,
    onWatch: onWatch,
    onLine: onLine,
    fontSize: 10,
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (arrival.planned) ...[
          const Icon(Icons.schedule, size: 14),
          const SizedBox(width: 2),
        ],
        Text(
          countdown(arrival.t),
          style: arrival.planned
              ? const TextStyle(fontStyle: FontStyle.italic)
              : null,
        ),
      ],
    ),
  );
}
