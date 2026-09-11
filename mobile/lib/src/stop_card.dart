/// One stop, from the bottom of the map: what is due, and what calls here.
library;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;

import 'due.dart';
import 'live.dart';
import 'models.dart';
import 'route_badge.dart';
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

  /// Whether it is pinned when the card opens; the card tracks its own taps
  /// from there, since the screen behind it cannot rebuild a sheet
  final bool pinned;

  /// The routes on the map, so a route this stop is served by can say whether
  /// it is already one of them
  final Set<int> watching;
  final VoidCallback onPin;
  final void Function(int route) onRoute;

  /// The same badge, held rather than tapped: a tap here picks the route to
  /// watch, so the line is on the long press, as it is in the route sheet
  final void Function(int route) onLine;

  @override
  State<StopCard> createState() => _StopCardState();
}

class _StopCardState extends State<StopCard> {
  late bool _pinned = widget.pinned;

  @override
  Widget build(BuildContext context) {
    final catalog = widget.catalog;
    final stop = widget.stop;
    final s = catalog.stops[stop];
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
                    s.name,
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
            if (s.code.isNotEmpty) Text(s.code),
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
                  GestureDetector(
                    onLongPress: () => widget.onLine(r),
                    child: ActionChip(
                      label: RouteBadge(route: catalog.routes[r], muted: true),
                      avatar: widget.watching.contains(r)
                          ? const Icon(Icons.check, size: 16)
                          : null,
                      onPressed: () => widget.onRoute(r),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
