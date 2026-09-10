/// One arrival, said the way a person waiting would say it.
library;

import 'package:flutter/material.dart';

import 'eta.dart';
import 'map_theme.dart';
import 'models.dart';
import 'theme.dart';

/// A route badge and how long until it calls. Half a minute away reads "now",
/// because "0 min" invites the reader to think it is late rather than here.
class Due extends StatelessWidget {
  const Due({super.key, required this.route, required this.arrival});

  final TransitRoute route;
  final Arrival arrival;

  @override
  Widget build(BuildContext context) => Chip(
    visualDensity: VisualDensity.compact,
    avatar: CircleAvatar(
      backgroundColor: routeColour(route.short, route.type),
      child: Text(
        route.short,
        style: const TextStyle(fontSize: 9, color: plate),
      ),
    ),
    label: Text(countdown(arrival.t)),
  );
}
