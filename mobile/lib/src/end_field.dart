/// An end of a journey, and the search that sets it.
library;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;
import 'package:latlong2/latlong.dart';

import 'api.dart';
import 'models.dart';
import 'route_badge.dart';
import 'sheets.dart' show askName;
import 'stop_search.dart';
import 'strings.dart';

enum End { from, to }

String endLabel(End end) => end == End.from ? txt.from : txt.to;

IconData endIcon(End end) =>
    end == End.from ? Icons.trip_origin : Icons.place_outlined;

/// An icon standing for a row's name, which it keeps as a tooltip.
class RowLabel extends StatelessWidget {
  const RowLabel({super.key, required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40,
    child: Tooltip(message: text, child: Icon(icon, size: 20)),
  );
}

/// An end of the journey: where it is, a search to change it, and a button
/// putting it where I am.
class EndField extends StatelessWidget {
  const EndField({
    super.key,
    required this.end,
    required this.at,
    this.aboard,
    required this.api,
    required this.catalog,
    required this.onPick,
    required this.onHere,
    required this.name,
    required this.places,
    required this.onPlace,
    required this.onSave,
  });

  final End end;
  final LatLng? at;

  /// The end is on board this vehicle rather than at a point
  final Aboard? aboard;
  final String? name;
  final Api api;
  final Catalog catalog;
  final VoidCallback onPick;
  final VoidCallback onHere;
  final List<Place> places;
  final void Function(LatLng at, String? name) onPlace;
  final void Function(String name, LatLng at) onSave;

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

  /// A search whose empty query offers where I am, the map, and the saved
  /// places - the way to an end that is not typed.
  Future<void> _find(BuildContext context) async {
    final here = at;
    final unsaved = here != null && _saved == null;
    final hit = await showSearch<Hit?>(
      context: context,
      delegate: StopSearch(
        api: api,
        catalog: catalog,
        onSave: onSave,
        idle: (sheet, done) {
          void then(VoidCallback act) {
            done();
            act();
          }

          return ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.my_location),
                title: Text(txt.useHere),
                onTap: () => then(onHere),
              ),
              ListTile(
                leading: const Icon(Icons.touch_app_outlined),
                title: Text(txt.chooseOnMap),
                onTap: () => then(onPick),
              ),
              if (unsaved)
                ListTile(
                  leading: const Icon(Icons.star_outline),
                  title: Text(txt.savePlace),
                  onTap: () => then(() => _name(context, here)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  txt.places,
                  style: material.Theme.of(sheet).textTheme.labelLarge,
                ),
              ),
              if (places.isEmpty)
                ListTile(
                  dense: true,
                  title: Text(
                    txt.noPlaces,
                    style: material.Theme.of(sheet).textTheme.bodySmall,
                  ),
                ),
              for (final p in places)
                ListTile(
                  leading: const Icon(Icons.star),
                  title: Text(p.name),
                  onTap: () => then(() => onPlace(p.at, null)),
                ),
            ],
          );
        },
      ),
    );
    switch (hit) {
      case StopHit(:final stop):
        final s = catalog.stops[stop];
        onPlace(LatLng(s.lat, s.lon), s.name);
      case PlaceHit(:final at, :final name):
        onPlace(at, name);
      case null:
    }
  }

  Future<void> _name(BuildContext context, LatLng where) async {
    final name = await askName(context, txt.namePlace, action: txt.saveHere);
    if (name != null && name.isNotEmpty) onSave(name, where);
  }

  Widget _label(String where) {
    final on = aboard?.route;
    if (aboard == null) return Text(where, overflow: TextOverflow.ellipsis);
    final route = on == null ? null : catalog.routes[on];
    return Row(
      children: [
        if (route != null) ...[
          RouteBadge(route: route, fontSize: 10),
          const SizedBox(width: 6),
        ],
        Flexible(child: Text(txt.aboard, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final where =
        _saved?.name ??
        name ??
        (at == null
            ? txt.findStop
            : '${at!.latitude.toStringAsFixed(4)}, '
                  '${at!.longitude.toStringAsFixed(4)}');
    return Row(
      children: [
        RowLabel(text: endLabel(end), icon: endIcon(end)),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _find(context),
            style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
            icon: const Icon(Icons.search, size: 18),
            label: _label(where),
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
