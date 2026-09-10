/// One arrival, said the way a person waiting would say it.
library;

import 'package:flutter/material.dart';

import 'eta.dart';
import 'models.dart';
import 'route_badge.dart';

/// A route badge and how long until it calls. Half a minute away reads "now",
/// because "0 min" invites the reader to think it is late rather than here.
class Due extends StatelessWidget {
  const Due({super.key, required this.route, required this.arrival});

  final TransitRoute route;
  final Arrival arrival;

  // The badge is the label rather than the avatar: an avatar is a circle sized
  // for one glyph, and this one is a glyph and a number
  @override
  Widget build(BuildContext context) => Chip(
    visualDensity: VisualDensity.compact,
    label: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RouteBadge(route: route, fontSize: 10),
        const SizedBox(width: 6),
        Text(countdown(arrival.t)),
      ],
    ),
  );
}
