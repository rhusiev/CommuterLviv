/// Where one vehicle goes next, and when it gets there.
///
/// The stop card asks a stop which vehicles are coming; this asks a vehicle
/// which stops are. Both read the same predictions, so the two cards cannot
/// disagree about a time.
///
/// The list is fetched rather than pushed: it changes once an epoch, which is
/// every 60 s, and a socket message per open card would carry the whole city's
/// predictions to move one of them.
library;

import 'dart:async';

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;

import 'api.dart';
import 'eta.dart';
import 'map_theme.dart';
import 'models.dart';
import 'strings.dart';
import 'theme.dart';

class VehicleCard extends StatefulWidget {
  const VehicleCard({
    super.key,
    required this.api,
    required this.catalog,
    required this.veh,
    required this.onStop,
  });

  final Api api;
  final Catalog catalog;

  /// The wire id, which is what the socket calls this vehicle
  final int veh;
  final void Function(int stop) onStop;

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
    // An epoch is 60 s and this is one small request, so the card follows the
    // model rather than freezing at the time it was opened
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
    final route = calls == null || calls.isEmpty
        ? null
        : widget.catalog.routes[calls.first.route];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (route != null) ...[
                  CircleAvatar(
                    backgroundColor: routeColour(route.short, route.type),
                    child: Text(
                      route.short,
                      style: const TextStyle(fontSize: 11, color: plate),
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
