/// The pinned stops, and what is due at each of them.
library;

import 'package:flutter/material.dart';

import 'due.dart';
import 'live.dart';
import 'models.dart';
import 'strings.dart';
import 'theme.dart';

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
      return Center(child: Text(txt.pinAStop));
    }
    // The bar and the tab pill float over this list rather than above it, so
    // the first and last stop have to be scrolled clear of them
    return AnimatedBuilder(
      animation: live,
      builder: (context, _) => ListView(
        padding: EdgeInsets.only(
          top: floatingTop(context),
          bottom: floatingBottom(context),
        ),
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
        ? Text(txt.nothingDue)
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
      tooltip: txt.unpin,
    ),
    onTap: onOpen,
  );
}
