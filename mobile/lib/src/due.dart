/// One arrival, said the way a person waiting would say it.
library;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;

import 'eta.dart';
import 'models.dart';
import 'map_theme.dart' show routeNumber;
import 'route_chip.dart';
import 'strings.dart';
import 'theme.dart' show accent;

/// A route's chip with how long until it calls.
class Due extends StatelessWidget {
  const Due({
    super.key,
    required this.route,
    required this.arrival,
    required this.watched,
    required this.onWatch,
    required this.onLine,
    this.lowFloor = false,
  });

  final TransitRoute route;
  final Arrival arrival;

  /// Mark a vehicle the feed calls low floor.
  final bool lowFloor;
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
          style: TextStyle(
            fontStyle: arrival.planned ? FontStyle.italic : null,
            // Amber, as an unsure ride is in the planner; [Doubts] says why
            color: arrival.doubt == null ? null : doubtColour,
          ),
        ),
        if (lowFloor && arrival.lowFloor) ...[
          const SizedBox(width: 2),
          Icon(
            Icons.accessible,
            size: 14,
            color: accent,
            semanticLabel: txt.lowFloor,
          ),
        ],
      ],
    ),
  );
}

/// The colour of a doubted time, and of the line saying why.
final doubtColour = Colors.amber.shade300;

/// Why an amber time is amber, one line a route, only while one is.
class Doubts extends StatelessWidget {
  const Doubts({super.key, required this.catalog, required this.due});

  final Catalog catalog;
  final Iterable<Arrival> due;

  @override
  Widget build(BuildContext context) {
    final doubted = due.where((a) => a.doubt != null).toList();
    if (doubted.isEmpty) return const SizedBox.shrink();
    final style = material.Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: doubtColour);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final a in doubted) Text(_said(a), style: style)],
      ),
    );
  }

  String _said(Arrival a) {
    final number = routeNumber(catalog.routes[a.route].short);
    return switch (a.doubt!) {
      Doubt.stuck => txt.doubtStuck(number),
      Doubt.silent => txt.doubtSilent(number),
    };
  }
}
