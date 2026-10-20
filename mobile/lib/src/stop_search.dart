/// Saved places and stops by name, scanned on every keystroke, and addresses
/// and shops from the service a quarter of a second after the typing stops.
/// Saved places come first, as the ones meant most often, then stops: they are
/// the thing the app is for, and both are already in hand. With nothing typed,
/// it offers the stops nearest the phone.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'api.dart';
import 'here.dart';
import 'match.dart';
import 'models.dart';
import 'sheets.dart' show askPlaceName;
import 'strings.dart';

/// How long the typing has to stop before the service is asked.
const searchDebounce = Duration(milliseconds: 250);

/// Metres: past this the phone is not near a stop, and likely not in the city.
const nearM = 2000.0;

/// How many of the nearest stops are listed.
const nearCount = 8;

/// The stops within [nearM] of [at], nearest first, each with its metres.
List<(int, double)> nearest(Catalog catalog, LatLng at) {
  const distance = Distance();
  final stops = catalog.stops;
  final near = [
    for (var i = 0; i < stops.length; i++)
      if (distance(at, LatLng(stops[i].lat, stops[i].lon)) case final m
          when m <= nearM)
        (i, m),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  return near.take(nearCount).toList();
}

/// What the search came back with: a stop in the catalog, or a point on it.
sealed class Hit {
  const Hit();
}

class StopHit extends Hit {
  const StopHit(this.stop);

  final int stop;
}

class PlaceHit extends Hit {
  const PlaceHit(this.at, this.name);

  final LatLng at;
  final String name;
}

class StopSearch extends SearchDelegate<Hit?> {
  StopSearch({
    required this.api,
    required this.catalog,
    required this.places,
    required this.onSave,
    this.idle,
    this.here,
  }) : super(searchFieldLabel: txt.findStop);

  final Api api;
  final Catalog catalog;
  final List<Place> places;
  final void Function(String name, LatLng at) onSave;

  /// What an empty query shows, given a way to close the search with nothing
  final Widget Function(BuildContext context, VoidCallback done)? idle;

  /// Where the phone is, for the stops near it, when [idle] is not shown
  final Here? here;

  /// The default paints the bar grey whatever the app's theme says
  @override
  ThemeData appBarTheme(BuildContext context) => super
      .appBarTheme(context)
      .copyWith(appBarTheme: Theme.of(context).appBarTheme);

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
  Widget buildSuggestions(BuildContext context) {
    void pick(Hit hit) => close(context, hit);
    if (query.trim().isNotEmpty) {
      return _Results(
        api: api,
        catalog: catalog,
        places: places,
        query: query.trim(),
        onPick: pick,
        onSave: onSave,
      );
    }
    if (idle case final idle?) return idle(context, () => close(context, null));
    if (here case final here?) {
      return _Near(here: here, catalog: catalog, onPick: pick, onSave: onSave);
    }
    return const SizedBox.shrink();
  }
}

/// Asks what to call [at], proposing [was], and saves it under that name.
Future<void> _saveAs(
  BuildContext context,
  void Function(String name, LatLng at) onSave,
  String was,
  LatLng at,
) async {
  final name = await askPlaceName(context, was: was);
  if (name != null) onSave(name, at);
}

/// The stops nearest the phone. Nothing is asked of it until the row is
/// tapped, unless it is already locating.
class _Near extends StatelessWidget {
  const _Near({
    required this.here,
    required this.catalog,
    required this.onPick,
    required this.onSave,
  });

  final Here here;
  final Catalog catalog;
  final void Function(Hit hit) onPick;
  final void Function(String name, LatLng at) onSave;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: here,
    builder: (context, _) {
      final at = here.fix?.point;
      if (here.state != Locating.on || at == null) return _ask(context);
      final near = nearest(catalog, at);
      if (near.isEmpty) return _Said(txt.nothingNear);
      return ListView(
        children: [
          _Heading(txt.nearMe),
          for (final (i, m) in near)
            _stop(context, catalog, i, txt.metres(m.round()), onPick, onSave),
        ],
      );
    },
  );

  Widget _ask(BuildContext context) {
    final waiting = here.state == Locating.waiting;
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.near_me_outlined),
          title: Text(txt.nearMe),
          subtitle: here.state == Locating.denied ? Text(txt.noLocation) : null,
          trailing: waiting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: waiting ? null : () => unawaited(here.start()),
        ),
      ],
    );
  }
}

/// Stop [i] as a row, with [under] beneath its name.
Widget _stop(
  BuildContext context,
  Catalog catalog,
  int i,
  String under,
  void Function(Hit hit) onPick,
  void Function(String name, LatLng at) onSave,
) {
  final s = catalog.stops[i];
  return _Row(
    icon: Icons.directions_bus_outlined,
    title: s.name,
    under: under,
    onTap: () => onPick(StopHit(i)),
    onSave: () => _saveAs(context, onSave, s.name, LatLng(s.lat, s.lon)),
  );
}

class _Results extends StatefulWidget {
  const _Results({
    required this.api,
    required this.catalog,
    required this.places,
    required this.query,
    required this.onPick,
    required this.onSave,
  });

  final Api api;
  final Catalog catalog;
  final List<Place> places;
  final String query;
  final void Function(Hit hit) onPick;
  final void Function(String name, LatLng at) onSave;

  @override
  State<_Results> createState() => _ResultsState();
}

class _ResultsState extends State<_Results> {
  late final _names = [for (final s in widget.catalog.stops) words(s.name)];
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
      _busy = widget.query.length >= minTyped;
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

  Future<void> _save(String was, LatLng at) =>
      _saveAs(context, widget.onSave, was, at);

  @override
  Widget build(BuildContext context) {
    final query = words(widget.query);
    if (query.isEmpty) return const SizedBox.shrink();
    final catalog = widget.catalog;
    final scored = [
      for (var i = 0; i < _names.length; i++)
        if (score(query, _names[i]) case final s when s > 0) (s, i),
    ];
    // Shorter names first among equals: "Ринок" before "Ринок Шувар"
    scored.sort(
      (a, b) => a.$1 != b.$1
          ? b.$1 - a.$1
          : catalog.stops[a.$2].name.length - catalog.stops[b.$2].name.length,
    );
    final stops = [for (final (_, i) in scored) i];
    final mine = matching(widget.places, widget.query);
    final rows = <Object>[
      if (mine.isNotEmpty) txt.places,
      ...mine,
      if (stops.isNotEmpty) txt.foundStops,
      ...stops,
      if (_found.isNotEmpty) txt.foundPlaces,
      ..._found,
    ];
    return Column(
      children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_failed) _Said(txt.noSearch),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              if (row is String) return _Heading(row);
              if (row is int) {
                return _stop(
                  context,
                  catalog,
                  row,
                  [
                    for (final r in catalog.stops[row].routes)
                      catalog.routes[r].short,
                  ].join(' · '),
                  widget.onPick,
                  widget.onSave,
                );
              }
              if (row is Place) {
                return _Row(
                  icon: Icons.star,
                  title: row.name,
                  under: '',
                  onTap: () => widget.onPick(PlaceHit(row.at, row.name)),
                );
              }
              final p = row as Found;
              return _Row(
                icon: Icons.place_outlined,
                title: p.name,
                under: p.where,
                onTap: () => widget.onPick(PlaceHit(p.at, p.name)),
                onSave: () => _save(p.name, p.at),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A section's title above its rows.
class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );
}

/// A line of small print in place of rows.
class _Said extends StatelessWidget {
  const _Said(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.under,
    required this.onTap,
    this.onSave,
  });

  final IconData icon;
  final String title;
  final String under;
  final VoidCallback onTap;

  /// Null for a place already saved
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title, overflow: TextOverflow.ellipsis),
    subtitle: under.isEmpty
        ? null
        : Text(under, overflow: TextOverflow.ellipsis),
    onTap: onTap,
    trailing: onSave == null
        ? null
        : IconButton(
            icon: const Icon(Icons.star_outline),
            tooltip: txt.savePlace,
            onPressed: onSave,
          ),
  );
}
