/// Everything kept by name: the saved places and the pinned stops, in the order
/// they are offered everywhere else. Each list goes up as a whole, so a rename
/// is the same one write as a reorder - which is what keeps a rename atomic,
/// since the name is the identity server-side.
library;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;
import 'package:latlong2/latlong.dart';

import 'models.dart';
import 'sheets.dart' show askName, manage;
import 'strings.dart';

class SavedSheet extends StatefulWidget {
  const SavedSheet({
    super.key,
    required this.catalog,
    required this.places,
    required this.pins,
    required this.onPlaces,
    required this.onPins,
    required this.onShowPlace,
    required this.onShowStop,
  });

  final Catalog catalog;
  final List<Place> places;

  /// Catalog positions, as the map holds them.
  final List<int> pins;

  final void Function(List<Place> places) onPlaces;
  final void Function(List<int> pins) onPins;
  final void Function(LatLng at) onShowPlace;
  final void Function(int stop) onShowStop;

  @override
  State<SavedSheet> createState() => _SavedSheetState();
}

class _SavedSheetState extends State<SavedSheet> {
  /// The sheet is its own route, built once, so it keeps its own copy and
  /// hands each change back.
  late List<Place> _places = [...widget.places];
  late List<int> _pins = [...widget.pins];

  void _putPlaces(List<Place> next) {
    setState(() => _places = next);
    widget.onPlaces(next);
  }

  void _putPins(List<int> next) {
    setState(() => _pins = next);
    widget.onPins(next);
  }

  Future<void> _rename(Place p) async {
    final name = await askName(context, txt.rename, was: p.name);
    if (name == null || name.isEmpty || name == p.name) return;
    _putPlaces([
      for (final q in _places)
        if (q.name == p.name) Place(name: name, at: q.at) else q,
    ]);
  }

  void _show(VoidCallback what) {
    Navigator.pop(context);
    what();
  }

  @override
  Widget build(BuildContext context) {
    final theme = material.Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (context, controller) => CustomScrollView(
        controller: controller,
        slivers: [
          if (_places.isEmpty && _pins.isEmpty)
            _Line(txt.nothingSaved, theme.textTheme.bodyMedium),
          if (_places.isNotEmpty) ...[
            _Line(txt.places, theme.textTheme.labelLarge),
            SliverReorderableList(
              itemCount: _places.length,
              onReorderItem: (from, to) =>
                  _putPlaces(_moved(_places, from, to)),
              itemBuilder: (context, i) {
                final p = _places[i];
                return _Row(
                  key: ValueKey(p.name),
                  index: i,
                  icon: Icons.place_outlined,
                  title: p.name,
                  under:
                      '${p.at.latitude.toStringAsFixed(4)}, '
                      '${p.at.longitude.toStringAsFixed(4)}',
                  onTap: () => _show(() => widget.onShowPlace(p.at)),
                  onRename: () => _rename(p),
                  onDelete: () async => _putPlaces([
                    for (final q in _places)
                      if (q.name != p.name) q,
                  ]),
                );
              },
            ),
          ],
          if (_pins.isNotEmpty) ...[
            _Line(txt.pinnedStops, theme.textTheme.labelLarge),
            SliverReorderableList(
              itemCount: _pins.length,
              onReorderItem: (from, to) => _putPins(_moved(_pins, from, to)),
              itemBuilder: (context, i) {
                final stop = widget.catalog.stops[_pins[i]];
                return _Row(
                  key: ValueKey(stop.id),
                  index: i,
                  icon: Icons.push_pin_outlined,
                  title: stop.name,
                  under: [
                    for (final r in stop.routes) widget.catalog.routes[r].short,
                  ].join(' · '),
                  onTap: () => _show(() => widget.onShowStop(_pins[i])),
                  onDelete: () async => _putPins([
                    for (final p in _pins)
                      if (p != _pins[i]) p,
                  ]),
                );
              },
            ),
          ],
          _Line(txt.showOnMap, theme.textTheme.bodySmall),
          _Line(txt.holdToManage, theme.textTheme.bodySmall, bottom: 24),
        ],
      ),
    );
  }
}

/// [to] is where the row lands once it has been lifted out, which is what
/// `onReorderItem` already accounts for.
List<T> _moved<T>(List<T> list, int from, int to) {
  final next = [...list];
  next.insert(to, next.removeAt(from));
  return next;
}

class _Line extends StatelessWidget {
  const _Line(this.text, this.style, {this.bottom = 8});

  final String text;
  final TextStyle? style;
  final double bottom;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottom),
      child: Text(text, style: style),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.index,
    required this.icon,
    required this.title,
    required this.under,
    required this.onTap,
    this.onRename,
    required this.onDelete,
  });

  final int index;
  final IconData icon;
  final String title;
  final String under;
  final VoidCallback onTap;
  final Future<void> Function()? onRename;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title, overflow: TextOverflow.ellipsis),
    subtitle: under.isEmpty
        ? null
        : Text(under, overflow: TextOverflow.ellipsis),
    onTap: onTap,
    onLongPress: () => manage(context, onRename: onRename, onDelete: onDelete),
    trailing: ReorderableDragStartListener(
      index: index,
      child: const Icon(Icons.drag_handle),
    ),
  );
}
