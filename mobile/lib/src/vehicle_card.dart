/// Where one vehicle goes next. Fetched rather than pushed: the predictions
/// change once an epoch.
library;

import 'dart:async';

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;

import 'api.dart';
import 'eta.dart';
import 'models.dart';
import 'route_badge.dart';
import 'strings.dart';

class VehicleCard extends StatefulWidget {
  const VehicleCard({
    super.key,
    required this.api,
    required this.catalog,
    required this.veh,
    required this.onStop,
    required this.onRoute,
  });

  final Api api;
  final Catalog catalog;

  final int veh;
  final void Function(int stop) onStop;

  final void Function(int route) onRoute;

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
    // An epoch is 60 s, so refresh rather than freeze at the time opened
    _again = Timer.periodic(const Duration(seconds: 60), (_) => _load());
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
                  Tooltip(
                    message: txt.showRoute,
                    child: InkWell(
                      onTap: () => widget.onRoute(at),
                      child: RouteBadge(route: route),
                    ),
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
                      title: Text(widget.catalog.stops[call.stop].name),
                      trailing: Text(countdown(call.t)),
                      onTap: () => widget.onStop(call.stop),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
