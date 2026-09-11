/// Stops by name, scanned on every keystroke, and addresses and shops from the
/// service a quarter of a second after the typing stops. Stops come first: they
/// are the thing the app is for, and they are already in hand.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'api.dart';
import 'models.dart';
import 'sheets.dart' show askName;
import 'strings.dart';

/// How long the typing has to stop before the service is asked.
const searchDebounce = Duration(milliseconds: 250);

/// Below this every prefix matches half the city, so nothing is asked.
const _shortest = 2;

/// What the search came back with: a stop in the catalog, or a point on it.
sealed class Hit {
  const Hit();
}

class StopHit extends Hit {
  const StopHit(this.stop);

  final int stop;
}

class PlaceHit extends Hit {
  const PlaceHit(this.at);

  final LatLng at;
}

class StopSearch extends SearchDelegate<Hit?> {
  StopSearch({required this.api, required this.catalog, required this.onSave})
    : super(searchFieldLabel: txt.findStop);

  final Api api;
  final Catalog catalog;
  final void Function(String name, LatLng at) onSave;

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const BackButtonIcon(),
  );

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) => _Results(
    api: api,
    catalog: catalog,
    query: query.trim(),
    onPick: (hit) => close(context, hit),
    onSave: onSave,
  );
}

class _Results extends StatefulWidget {
  const _Results({
    required this.api,
    required this.catalog,
    required this.query,
    required this.onPick,
    required this.onSave,
  });

  final Api api;
  final Catalog catalog;
  final String query;
  final void Function(Hit hit) onPick;
  final void Function(String name, LatLng at) onSave;

  @override
  State<_Results> createState() => _ResultsState();
}

class _ResultsState extends State<_Results> {
  List<Found> _found = const [];
  bool _busy = false;
  bool _failed = false;
  Timer? _timer;

  @override
  void didUpdateWidget(_Results old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _restart();
  }

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    setState(() {
      _found = const [];
      _failed = false;
      _busy = widget.query.length >= _shortest;
    });
    if (_busy) _timer = Timer(searchDebounce, () => unawaited(_ask()));
  }

  Future<void> _ask() async {
    final asked = widget.query;
    try {
      final got = await widget.api.find(asked);
      if (mounted && asked == widget.query) {
        setState(() {
          _found = got;
          _busy = false;
        });
      }
    } on Exception {
      if (mounted && asked == widget.query) {
        setState(() {
          _failed = true;
          _busy = false;
        });
      }
    }
  }

  Future<void> _save(String was, LatLng at) async {
    final name = await askName(
      context,
      txt.namePlace,
      was: was,
      action: txt.saveHere,
    );
    if (name != null && name.isNotEmpty) widget.onSave(name, at);
  }

  @override
  Widget build(BuildContext context) {
    final needle = widget.query.toLowerCase();
    if (needle.isEmpty) return const SizedBox.shrink();
    final catalog = widget.catalog;
    final stops = [
      for (var i = 0; i < catalog.stops.length; i++)
        if (catalog.stops[i].name.toLowerCase().contains(needle)) i,
    ];
    final rows = <Object>[
      if (stops.isNotEmpty) txt.foundStops,
      ...stops,
      if (_found.isNotEmpty) txt.foundPlaces,
      ..._found,
    ];
    return Column(
      children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_failed)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              txt.noSearch,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              if (row is String) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    row,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                );
              }
              if (row is int) {
                final s = catalog.stops[row];
                return _Row(
                  icon: Icons.directions_bus_outlined,
                  title: s.name,
                  under: [for (final r in s.routes) catalog.routes[r].short]
                      .join(' · '),
                  onTap: () => widget.onPick(StopHit(row)),
                  onSave: () => _save(s.name, LatLng(s.lat, s.lon)),
                );
              }
              final p = row as Found;
              return _Row(
                icon: Icons.place_outlined,
                title: p.name,
                under: p.where,
                onTap: () => widget.onPick(PlaceHit(p.at)),
                onSave: () => _save(p.name, p.at),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.under,
    required this.onTap,
    required this.onSave,
  });

  final IconData icon;
  final String title;
  final String under;
  final VoidCallback onTap;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title, overflow: TextOverflow.ellipsis),
    subtitle: under.isEmpty
        ? null
        : Text(under, overflow: TextOverflow.ellipsis),
    onTap: onTap,
    trailing: IconButton(
      icon: const Icon(Icons.star_outline),
      tooltip: txt.savePlace,
      onPressed: onSave,
    ),
  );
}
