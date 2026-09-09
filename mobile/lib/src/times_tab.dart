/// The pinned stops, and what is due at each of them.
library;

import 'package:flutter/material.dart';

import 'due.dart';
import 'live.dart';
import 'models.dart';

class TimesTab extends StatelessWidget {
  const TimesTab({
    super.key,
    required this.catalog,
    required this.live,
    required this.pins,
    required this.onUnpin,
    required this.onOpen,
  });

  final Catalog catalog;
  final Live live;

  /// Catalog positions, in the order they were pinned
  final List<int> pins;
  final void Function(int stop) onUnpin;
  final void Function(int stop) onOpen;

  @override
  Widget build(BuildContext context) {
    if (pins.isEmpty) {
      return const Center(child: Text('Pin a stop and its times show up here'));
    }
    return AnimatedBuilder(
      animation: live,
      builder: (context, _) => ListView(
        children: [
          for (final stop in pins)
            _StopTile(
              catalog: catalog,
              stop: stop,
              arrivals: live.arrivals[stop] ?? const [],
              onUnpin: () => onUnpin(stop),
              onOpen: () => onOpen(stop),
            ),
        ],
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.catalog,
    required this.stop,
    required this.arrivals,
    required this.onUnpin,
    required this.onOpen,
  });

  final Catalog catalog;
  final int stop;
  final List<Arrival> arrivals;
  final VoidCallback onUnpin;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(catalog.stops[stop].name),
    subtitle: arrivals.isEmpty
        ? const Text('nothing due')
        : Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final a in arrivals.take(6))
                Due(route: catalog.routes[a.route], arrival: a),
            ],
          ),
    trailing: IconButton(
      onPressed: onUnpin,
      icon: const Icon(Icons.push_pin),
      tooltip: 'Unpin',
    ),
    onTap: onOpen,
  );
}
