/// Door to door: two points, and the ways between them. Each ride says whether
/// it came from a tracked vehicle or from the timetable.
library;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;
import 'package:latlong2/latlong.dart';

import 'api.dart';
import 'models.dart';
import 'route_badge.dart';
import 'sheets.dart' show askName;
import 'strings.dart';
import 'theme.dart';

enum End { from, to }

/// What a ride rests on, in a word under the route.
String legPart(Confidence confidence) => switch (confidence) {
  Confidence.live => txt.livePart,
  Confidence.schedule => txt.schedulePart,
  Confidence.quiet => txt.quietPart,
};

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
    required this.onLine,
    required this.places,
    required this.onSave,
    required this.onForget,
    required this.onPlace,
    required this.onClose,
  });

  final Api api;
  final Catalog catalog;
  final LatLng? from;
  final LatLng? to;

  final End? picking;
  final void Function(End? which) onPick;
  final VoidCallback onSwap;
  final void Function(End which) onHere;
  final void Function(int stop) onStop;

  final void Function(int route) onLine;

  final List<Place> places;
  final void Function(String name, LatLng at) onSave;
  final void Function(String name) onForget;
  final void Function(End end, LatLng at) onPlace;
  final VoidCallback onClose;

  @override
  State<JourneyPanel> createState() => _JourneyPanelState();
}

class _JourneyPanelState extends State<JourneyPanel> {
  List<Journey>? _options;
  bool _busy = false;
  String? _failed;

  /// Unix seconds to leave at; null is now, which is what the server assumes.
  int? _at;

  @override
  void didUpdateWidget(JourneyPanel old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from || old.to != widget.to) _forget();
  }

  void _forget() {
    _options = null;
    _failed = null;
  }

  /// A time already past today is meant for tomorrow, which is as far ahead as
  /// the server plans.
  Future<void> _pickTime() async {
    final now = DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _at == null ? now : DateTime.fromMillisecondsSinceEpoch(_at! * 1000),
      ),
    );
    if (picked == null) return;
    var at = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
    if (at.isBefore(now)) at = at.add(const Duration(days: 1));
    setState(() {
      _at = at.millisecondsSinceEpoch ~/ 1000;
      _forget();
    });
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
      final got = await widget.api.plan(from, to, at: _at);
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
            for (final end in End.values)
              _End(
                label: end == End.from ? txt.from : txt.to,
                at: end == End.from ? widget.from : widget.to,
                picking: widget.picking == end,
                onPick: () => widget.onPick(widget.picking == end ? null : end),
                onHere: () => widget.onHere(end),
                places: widget.places,
                onPlace: (at) => widget.onPlace(end, at),
                onSave: widget.onSave,
                onForget: widget.onForget,
              ),
            Row(
              children: [
                SizedBox(width: 56, child: Text(txt.departAt)),
                InputChip(
                  avatar: const Icon(Icons.schedule, size: 18),
                  label: Text(_at == null ? txt.now : _clock(_at!)),
                  onPressed: _pickTime,
                  onDeleted: _at == null
                      ? null
                      : () => setState(() {
                          _at = null;
                          _forget();
                        }),
                ),
              ],
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
                          onLine: widget.onLine,
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
    required this.places,
    required this.onPlace,
    required this.onSave,
    required this.onForget,
  });

  final String label;
  final LatLng? at;
  final bool picking;
  final VoidCallback onPick;
  final VoidCallback onHere;
  final List<Place> places;
  final void Function(LatLng at) onPlace;
  final void Function(String name, LatLng at) onSave;
  final void Function(String name) onForget;

  /// Within about eleven metres.
  static const _same = 1e-4;

  Place? get _saved => places
      .where(
        (p) =>
            at != null &&
            (p.at.latitude - at!.latitude).abs() < _same &&
            (p.at.longitude - at!.longitude).abs() < _same,
      )
      .firstOrNull;

  Future<void> _menu(BuildContext context) async {
    final here = at;
    final chosen = await showModalBottomSheet<Object>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            if (places.isEmpty)
              ListTile(
                dense: true,
                title: Text(
                  txt.noPlaces,
                  style: material.Theme.of(context).textTheme.bodySmall,
                ),
              ),
            for (final p in places)
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(p.name),
                onTap: () => Navigator.pop(context, p),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: txt.forget,
                  onPressed: () {
                    Navigator.pop(context);
                    onForget(p.name);
                  },
                ),
              ),
            if (here != null && _saved == null) ...[
              const Divider(height: 8),
              ListTile(
                leading: const Icon(Icons.star_outline),
                title: Text(txt.savePlace),
                onTap: () => Navigator.pop(context, here),
              ),
            ],
          ],
        ),
      ),
    );
    if (chosen is Place) onPlace(chosen.at);
    if (chosen is LatLng && context.mounted) await _name(context, chosen);
  }

  Future<void> _name(BuildContext context, LatLng where) async {
    final name = await askName(context, txt.namePlace, action: txt.saveHere);
    if (name != null && name.isNotEmpty) onSave(name, where);
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    final where =
        saved?.name ??
        (at == null
            ? txt.tapMap
            : '${at!.latitude.toStringAsFixed(4)}, '
                  '${at!.longitude.toStringAsFixed(4)}');
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
          onPressed: () => _menu(context),
          icon: Icon(saved == null ? Icons.star_outline : Icons.star),
          tooltip: txt.places,
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
    required this.onLine,
  });

  final Journey journey;
  final Catalog catalog;
  final void Function(int stop) onStop;

  final void Function(int route) onLine;

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
              _LegRow(
                leg: leg,
                catalog: catalog,
                onStop: onStop,
                onLine: onLine,
              ),
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
    required this.onLine,
  });

  final Leg leg;
  final Catalog catalog;
  final void Function(int stop) onStop;

  final void Function(int route) onLine;

  @override
  Widget build(BuildContext context) {
    final theme = material.Theme.of(context);
    final small = theme.textTheme.bodySmall;
    // A walk between two rides is a leg of its own on the wire, so it is one
    // here too: its own duration, and the stop it ends at
    final where = leg.b < 0 ? txt.toDoor : catalog.stops[leg.b].name;
    return InkWell(
      onTap: leg.b < 0 ? null : () => onStop(leg.b),
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            if (leg.walking)
              SizedBox(
                width: 92,
                child: Text(
                  txt.walkLeg(_mins(leg.arr - leg.dep)),
                  style: small,
                ),
              )
            else ...[
              SizedBox(width: 44, child: Text(_clock(leg.dep))),
              // Inside a row that opens the stop, so the badge takes its own
              // taps
              InkWell(
                onTap: () => onLine(leg.route!),
                borderRadius: BorderRadius.circular(6),
                child: RouteBadge(
                  route: catalog.routes[leg.route!],
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(where, overflow: TextOverflow.ellipsis)),
            if (!leg.walking)
              Text(
                legPart(leg.confidence),
                style: leg.confidence == Confidence.quiet
                    ? small?.copyWith(color: theme.colorScheme.error)
                    : small,
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
