/// One stop, from the bottom of the map: what is due, and what calls here.
library;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;

import 'due.dart';
import 'live.dart';
import 'models.dart';
import 'route_chip.dart';
import 'strings.dart';

class StopCard extends StatefulWidget {
  const StopCard({
    super.key,
    required this.catalog,
    required this.live,
    required this.stop,
    required this.pinned,
    required this.watching,
    required this.onPin,
    required this.onRoute,
    required this.onLine,
  });

  final Catalog catalog;
  final Live live;
  final int stop;

  /// Only the initial state: the screen behind cannot rebuild a sheet, so the
  /// card tracks its own taps from here.
  final bool pinned;

  /// The routes watched: the screen behind changes this set in place on
  /// [onRoute], and the card rebuilds itself after it.
  final Set<int> watching;
  final VoidCallback onPin;

  /// Watches the route or stops watching it, from a chip's body.
  final void Function(int route) onRoute;

  /// The line, from a chip's `›`.
  final void Function(int route) onLine;

  @override
  State<StopCard> createState() => _StopCardState();
}

class _StopCardState extends State<StopCard> {
  late bool _pinned = widget.pinned;

  void _watch(int route) {
    widget.onRoute(route);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final catalog = widget.catalog;
    final stop = widget.stop;
    final s = catalog.stops[stop];
    final title = s.title;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title.name,
                    style: material.Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() => _pinned = !_pinned);
                    widget.onPin();
                  },
                  icon: Icon(
                    _pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  ),
                  tooltip: _pinned ? txt.unpin : txt.pin,
                ),
              ],
            ),
            if (title.code.isNotEmpty) Text(title.code),
            const SizedBox(height: 8),
            AnimatedBuilder(
              animation: widget.live,
              builder: (context, _) {
                final due = widget.live.arrivals[stop] ?? const <Arrival>[];
                if (due.isEmpty) {
                  return Text(txt.nothingDueWatched);
                }
                return Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final a in due.take(8))
                      Due(
                        route: catalog.routes[a.route],
                        arrival: a,
                        watched: widget.watching.contains(a.route),
                        onWatch: () => _watch(a.route),
                        onLine: () => widget.onLine(a.route),
                      ),
                  ],
                );
              },
            ),
            const Divider(height: 24),
            Text(
              txt.callsHere,
              style: material.Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final r in s.routes)
                  RouteChip(
                    route: catalog.routes[r],
                    watched: widget.watching.contains(r),
                    onWatch: () => _watch(r),
                    onLine: () => widget.onLine(r),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
