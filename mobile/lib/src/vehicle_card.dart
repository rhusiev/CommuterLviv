/// Where one vehicle goes next. Fetched rather than pushed: the predictions
/// change once an epoch.
library;

import 'dart:async';

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;

import 'api.dart';
import 'eta.dart';
import 'models.dart';
import 'route_chip.dart';
import 'strings.dart';
import 'theme.dart' show accent;

class VehicleCard extends StatefulWidget {
  const VehicleCard({
    super.key,
    required this.api,
    required this.catalog,
    required this.veh,
    required this.onStop,
    required this.watching,
    required this.onWatch,
    required this.onRoute,
    required this.onAboard,
    this.following = false,
    this.onFollow,
    this.lowFloor = false,
  });

  final Api api;
  final Catalog catalog;

  final int veh;
  final void Function(int stop) onStop;

  /// The routes watched: the screen behind changes this set in place on
  /// [onWatch], and the card rebuilds itself after it.
  final Set<int> watching;
  final void Function(int route) onWatch;

  /// The line, from the route chip's `›`.
  final void Function(int route) onRoute;

  /// Plans a journey from on board it
  final void Function(Aboard from) onAboard;

  /// The map keeps it in the middle; null offers no following.
  final bool following;
  final ValueChanged<bool>? onFollow;

  /// Mark it if the feed calls it low floor.
  final bool lowFloor;

  @override
  State<VehicleCard> createState() => _VehicleCardState();
}

class _VehicleCardState extends State<VehicleCard> {
  VehicleSaid? _said;
  bool _gone = false;

  /// Its own: the screen behind cannot rebuild a sheet
  late bool _following = widget.following;
  Timer? _again;

  @override
  void initState() {
    super.initState();
    _load();
    // Refreshed every epoch rather than frozen at the time opened
    _again = Timer.periodic(epoch, (_) => _load());
  }

  @override
  void dispose() {
    _again?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final said = await widget.api.vehicle(widget.veh);
      if (!mounted) return;
      setState(() {
        _said = said;
        _gone = said.calls.isEmpty;
      });
    } catch (_) {
      if (mounted) setState(() => _gone = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final said = _said;
    final calls = said?.calls;
    final at = calls == null || calls.isEmpty ? null : calls.first.route;
    final route = at == null ? null : widget.catalog.routes[at];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (route != null && at != null) ...[
                  RouteChip(
                    route: route,
                    watched: widget.watching.contains(at),
                    onWatch: () {
                      widget.onWatch(at);
                      setState(() {});
                    },
                    onLine: () => widget.onRoute(at),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        txt.stopsAhead,
                        style: material.Theme.of(context).textTheme.titleLarge,
                      ),
                      if (route != null)
                        _Named(route.long, said, widget.lowFloor),
                      if (said?.seen case final seen?) _LastSeen(seen),
                    ],
                  ),
                ),
                if (widget.onFollow case final onFollow?)
                  IconButton(
                    tooltip: txt.followVehicle,
                    isSelected: _following,
                    onPressed: () {
                      setState(() => _following = !_following);
                      onFollow(_following);
                    },
                    icon: const Icon(Icons.center_focus_weak),
                    selectedIcon: const Icon(Icons.center_focus_strong),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_gone)
              Text(txt.vehicleGone)
            else if (calls == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(minHeight: 2),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: calls.length,
                  itemBuilder: (context, i) {
                    final call = calls[i];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(widget.catalog.stopName(call.stop)),
                      trailing: Text(countdown(call.t)),
                      onTap: () => widget.onStop(call.stop),
                    );
                  },
                ),
              ),
            if (calls != null && calls.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: Tooltip(
                  message: txt.onItHint,
                  child: FilledButton.tonal(
                    onPressed: () => widget.onAboard(Aboard(widget.veh, at)),
                    child: Text(txt.onIt),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The line's name, then the vehicle's fleet number and its low-floor mark.
class _Named extends StatelessWidget {
  const _Named(this.long, this.said, this.lowFloor);

  final String long;
  final VehicleSaid? said;
  final bool lowFloor;

  @override
  Widget build(BuildContext context) {
    final fleet = said?.fleet;
    return Row(
      children: [
        Flexible(
          child: Text(long, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        if (fleet != null) Text(' · ${txt.fleet(fleet)}'),
        if (lowFloor && (said?.lowFloor ?? false))
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(
              Icons.accessible,
              size: 16,
              color: accent,
              semanticLabel: txt.lowFloor,
            ),
          ),
      ],
    );
  }
}

/// A report older than this and the card says when it was: the map fades the
/// vehicle from the same age (`FRESH` in `live/state.py`).
const _staleS = 30;

/// When the vehicle last reported, said only once that is worth knowing.
class _LastSeen extends StatelessWidget {
  const _LastSeen(this.seen);

  /// Unix seconds
  final int seen;

  @override
  Widget build(BuildContext context) {
    final ago = DateTime.now().millisecondsSinceEpoch ~/ 1000 - seen;
    if (ago < _staleS) return const SizedBox.shrink();
    final said = ago < Duration.secondsPerMinute
        ? txt.seconds(ago)
        : txt.minutes(ago ~/ Duration.secondsPerMinute);
    return Text(
      txt.lastSeen(said),
      style: TextStyle(color: Colors.amber.shade300),
    );
  }
}
