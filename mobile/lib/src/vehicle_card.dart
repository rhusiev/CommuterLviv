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

  @override
  State<VehicleCard> createState() => _VehicleCardState();
}

class _VehicleCardState extends State<VehicleCard> {
  List<Call>? _calls;
  bool _gone = false;
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
      final calls = await widget.api.vehicle(widget.veh);
      if (!mounted) return;
      setState(() {
        _calls = calls;
        _gone = calls.isEmpty;
      });
    } catch (_) {
      if (mounted) setState(() => _gone = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final calls = _calls;
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
                        Text(
                          route.long,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
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
