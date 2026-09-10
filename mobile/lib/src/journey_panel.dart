/// Door to door: two points, and the ways between them.
///
/// The points are set by tapping the map, which is the one gesture that needs
/// no address database - this service has stop names and nothing else, and a
/// planner that could only start from a stop would answer a question nobody
/// asked.
///
/// Each ride says whether it came from a tracked vehicle or from the timetable.
/// That is not decoration: past three quarters of an hour the model has nothing
/// to say and the leg is the schedule's guess, and somebody deciding whether to
/// run for a bus deserves to know which of the two they are reading.
library;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;
import 'package:latlong2/latlong.dart';

import 'api.dart';
import 'map_theme.dart';
import 'models.dart';
import 'strings.dart';
import 'theme.dart';

/// Which end of a journey a tap or a fix is for
enum End { from, to }

class JourneyPanel extends StatefulWidget {
  const JourneyPanel({
    super.key,
    required this.api,
    required this.catalog,
    required this.from,
    required this.to,
    required this.picking,
    required this.onPick,
    required this.onSwap,
    required this.onHere,
    required this.onStop,
    required this.onClose,
  });

  final Api api;
  final Catalog catalog;
  final LatLng? from;
  final LatLng? to;

  /// Which end the next tap on the map sets, if either
  final End? picking;
  final void Function(End? which) onPick;
  final VoidCallback onSwap;
  final void Function(End which) onHere;
  final void Function(int stop) onStop;
  final VoidCallback onClose;

  @override
  State<JourneyPanel> createState() => _JourneyPanelState();
}

class _JourneyPanelState extends State<JourneyPanel> {
  List<Journey>? _options;
  bool _busy = false;
  String? _failed;

  @override
  void didUpdateWidget(JourneyPanel old) {
    super.didUpdateWidget(old);
    // A moved end makes the answer on screen an answer to a different question
    if (old.from != widget.from || old.to != widget.to) {
      _options = null;
      _failed = null;
    }
  }

  Future<void> _search() async {
    final from = widget.from;
    final to = widget.to;
    if (from == null || to == null) return;
    setState(() {
      _busy = true;
      _failed = null;
    });
    try {
      final got = await widget.api.plan(from, to);
      if (mounted) setState(() => _options = got);
    } on ApiError catch (e) {
      if (mounted) setState(() => _failed = e.message);
    } on Exception {
      if (mounted) setState(() => _failed = txt.unreachable(widget.api.base));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = widget.from != null && widget.to != null;
    // Rounded on all four corners and left to float: whoever places it keeps it
    // off the edges, so it is a card over the city rather than a drawer out of
    // the bottom of the screen
    return Material(
      elevation: 8,
      color: panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(panelRadius),
        side: const BorderSide(color: hair),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  txt.plan,
                  style: material.Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  onPressed: widget.onSwap,
                  icon: const Icon(Icons.swap_vert),
                  tooltip: txt.swap,
                ),
                IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            _End(
              label: txt.from,
              at: widget.from,
              picking: widget.picking == End.from,
              onPick: () =>
                  widget.onPick(widget.picking == End.from ? null : End.from),
              onHere: () => widget.onHere(End.from),
            ),
            _End(
              label: txt.to,
              at: widget.to,
              picking: widget.picking == End.to,
              onPick: () =>
                  widget.onPick(widget.picking == End.to ? null : End.to),
              onHere: () => widget.onHere(End.to),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: ready && !_busy ? _search : null,
                child: Text(_busy ? txt.searching : txt.findRoute),
              ),
            ),
            if (_failed != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _failed!,
                  style: TextStyle(
                    color: material.Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            if (_options != null)
              Flexible(
                child: _options!.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(txt.noJourney),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _options!.length,
                        itemBuilder: (_, i) => _Option(
                          journey: _options![i],
                          catalog: widget.catalog,
                          onStop: widget.onStop,
                        ),
                      ),
              )
            else if (_failed == null && !_busy)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  txt.planHint,
                  style: material.Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _End extends StatelessWidget {
  const _End({
    required this.label,
    required this.at,
    required this.picking,
    required this.onPick,
    required this.onHere,
  });

  final String label;
  final LatLng? at;
  final bool picking;
  final VoidCallback onPick;
  final VoidCallback onHere;

  @override
  Widget build(BuildContext context) {
    final where = at == null
        ? txt.tapMap
        : '${at!.latitude.toStringAsFixed(4)}, '
              '${at!.longitude.toStringAsFixed(4)}';
    return Row(
      children: [
        SizedBox(width: 56, child: Text(label)),
        Expanded(
          child: OutlinedButton(
            onPressed: onPick,
            style: OutlinedButton.styleFrom(
              backgroundColor: picking
                  ? material.Theme.of(context).colorScheme.primaryContainer
                  : null,
              alignment: Alignment.centerLeft,
            ),
            child: Text(where, overflow: TextOverflow.ellipsis),
          ),
        ),
        IconButton(
          onPressed: onHere,
          icon: const Icon(Icons.my_location),
          tooltip: txt.useHere,
        ),
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.journey,
    required this.catalog,
    required this.onStop,
  });

  final Journey journey;
  final Catalog catalog;
  final void Function(int stop) onStop;

  @override
  Widget build(BuildContext context) {
    final changes = journey.rides - 1;
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  txt.minutes(_mins(journey.arr - journey.dep)),
                  style: material.Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 8),
                Text('${_clock(journey.dep)} - ${_clock(journey.arr)}'),
                const Spacer(),
                Text(
                  journey.rides == 0
                      ? txt.wholeWalk
                      : changes <= 0
                      ? txt.noChange
                      : txt.changeCount(changes),
                  style: material.Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            for (final leg in journey.legs)
              _LegRow(leg: leg, catalog: catalog, onStop: onStop),
          ],
        ),
      ),
    );
  }
}

class _LegRow extends StatelessWidget {
  const _LegRow({
    required this.leg,
    required this.catalog,
    required this.onStop,
  });

  final Leg leg;
  final Catalog catalog;
  final void Function(int stop) onStop;

  @override
  Widget build(BuildContext context) {
    final where = leg.b < 0 ? txt.toDoor : catalog.stops[leg.b].name;
    if (leg.walking) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(
                txt.walkLeg(_mins(leg.arr - leg.dep)),
                style: material.Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Expanded(child: Text(where, overflow: TextOverflow.ellipsis)),
          ],
        ),
      );
    }
    final route = catalog.routes[leg.route!];
    return InkWell(
      onTap: leg.b < 0 ? null : () => onStop(leg.b),
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            SizedBox(width: 44, child: Text(_clock(leg.dep))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: routeColour(route.short, route.type),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                route.short,
                style: const TextStyle(fontSize: 11, color: plate),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(where, overflow: TextOverflow.ellipsis)),
            Text(
              leg.live ? txt.livePart : txt.schedulePart,
              style: material.Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

int _mins(int seconds) => seconds < 60 ? 1 : (seconds / 60).round();

String _clock(int t) {
  final at = DateTime.fromMillisecondsSinceEpoch(t * 1000);
  return '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
}
