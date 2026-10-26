/// Everything that is the account's own: the pinned stops with what is due
/// there, the saved places and the route sets, one at a time under a switch,
/// with the account itself beside it. Each list goes up as a whole, so a rename is the same one write as a
/// reorder - which is what keeps a rename atomic, since the name is the
/// identity server-side.
library;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;

import 'due.dart';
import 'live.dart';
import 'models.dart';
import 'point_label.dart';
import 'sheets.dart' show askName, manage;
import 'strings.dart';
import 'theme.dart';

/// How many arrivals a pinned stop shows at most.
const _dueShown = 6;

/// Which of the account's lists is shown.
enum MineSection { stops, places, sets }

class MineTab extends StatefulWidget {
  const MineTab({
    super.key,
    required this.catalog,
    required this.live,
    required this.pins,
    required this.onPins,
    required this.onStop,
    required this.watching,
    required this.onWatch,
    required this.onLine,
    required this.places,
    required this.onPlaces,
    required this.onPlace,
    required this.sets,
    required this.onActivate,
    required this.onRename,
    required this.onDelete,
    required this.username,
    required this.onAccount,
  });

  final Catalog catalog;
  final Live live;

  /// Catalog positions, as the map holds them.
  final List<int> pins;
  final void Function(List<int> pins) onPins;
  final void Function(int stop) onStop;

  final Set<int> watching;
  final void Function(int route) onWatch;
  final void Function(int route) onLine;

  final List<Place> places;
  final void Function(List<Place> places) onPlaces;
  final void Function(Place place) onPlace;

  final Sets? sets;
  final void Function(RouteSet set) onActivate;
  final Future<void> Function(RouteSet set, String name) onRename;
  final Future<void> Function(RouteSet set) onDelete;

  final String username;
  final VoidCallback onAccount;

  @override
  State<MineTab> createState() => _MineTabState();
}

class _MineTabState extends State<MineTab> {
  /// The order just dragged to, shown until the screen hands the saved list
  /// back, so a row does not jump back while the write is under way.
  List<Place>? _placed;
  var _section = MineSection.stops;

  @override
  void didUpdateWidget(MineTab old) {
    super.didUpdateWidget(old);
    if (old.places != widget.places) _placed = null;
  }

  List<Place> get _places => _placed ?? widget.places;

  void _putPlaces(List<Place> next) {
    setState(() => _placed = next);
    widget.onPlaces(next);
  }

  Future<void> _renamePlace(Place p) async {
    final name = await askName(context, txt.rename, was: p.name);
    if (name == null || name.isEmpty || name == p.name) return;
    // Names compared as the server keys them, trimmed: the other place of
    // that name would be dropped there
    if (_places.any((q) => q.name != p.name && q.name.trim() == name)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(txt.placeNameTaken)));
      }
      return;
    }
    _putPlaces([
      for (final q in _places)
        if (q.name == p.name) Place(name: name, at: q.at) else q,
    ]);
  }

  Future<void> _renameSet(RouteSet set) async {
    final name = await askName(context, txt.rename, was: set.name);
    if (name == null || name.isEmpty || name == set.name) return;
    await widget.onRename(set, name);
  }

  @override
  Widget build(BuildContext context) {
    // The bar and the tab pill float over this list, so the ends need clearance
    return CustomScrollView(
      slivers: [
        SliverPadding(padding: EdgeInsets.only(top: floatingTop(context))),
        SliverToBoxAdapter(child: _switch()),
        ...switch (_section) {
          MineSection.stops => _stops(),
          MineSection.places => _placeRows(),
          MineSection.sets => _setRows(context),
        },
        SliverPadding(
          padding: EdgeInsets.only(bottom: floatingBottom(context)),
        ),
      ],
    );
  }

  Widget _switch() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 4, 4),
    child: Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 6,
            children: [
              for (final (section, label) in [
                (MineSection.stops, txt.mineStops),
                (MineSection.places, txt.minePlaces),
                (MineSection.sets, txt.sets),
              ])
                ChoiceChip(
                  label: Text(label),
                  showCheckmark: false,
                  selected: _section == section,
                  onSelected: (_) => setState(() => _section = section),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: widget.onAccount,
          icon: const Icon(Icons.manage_accounts_outlined),
          tooltip: '${txt.account}: ${widget.username}',
        ),
      ],
    ),
  );

  List<Widget> _stops() {
    final pins = widget.pins;
    if (pins.isEmpty) return [_Hint(txt.pinAStop)];
    return [
      AnimatedBuilder(
        animation: widget.live,
        builder: (context, _) => SliverReorderableList(
          itemCount: pins.length,
          onReorderItem: (from, to) => widget.onPins(_moved(pins, from, to)),
          itemBuilder: (context, i) => _StopTile(
            key: ValueKey(widget.catalog.stops[pins[i]].id),
            index: i,
            catalog: widget.catalog,
            stop: pins[i],
            arrivals: widget.live.arrivals[pins[i]] ?? const [],
            onUnpin: () => widget.onPins([
              for (final p in pins)
                if (p != pins[i]) p,
            ]),
            onOpen: () => widget.onStop(pins[i]),
            watching: widget.watching,
            onWatch: widget.onWatch,
            onLine: widget.onLine,
          ),
        ),
      ),
      _Hint(txt.holdToUnpin),
    ];
  }

  List<Widget> _placeRows() {
    final places = _places;
    if (places.isEmpty) return [_Hint(txt.saveHow)];
    return [
      SliverReorderableList(
        itemCount: places.length,
        onReorderItem: (from, to) => _putPlaces(_moved(places, from, to)),
        itemBuilder: (context, i) {
          final p = places[i];
          return _Row(
            key: ValueKey(p.name),
            index: i,
            icon: Icons.place_outlined,
            title: p.name,
            under: pointLabel(widget.catalog, p.at),
            onTap: () => widget.onPlace(p),
            onRename: () => _renamePlace(p),
            onDelete: () async => _putPlaces([
              for (final q in places)
                if (q.name != p.name) q,
            ]),
          );
        },
      ),
      _Hint(txt.holdToManage),
    ];
  }

  List<Widget> _setRows(BuildContext context) {
    final sets = widget.sets;
    if (sets == null || sets.sets.isEmpty) {
      return [_Hint(txt.noSets)];
    }
    return [
      SliverList.list(
        children: [
          for (final s in sets.sets)
            ListTile(
              leading: Icon(
                s.id == sets.active
                    ? Icons.check_circle
                    : Icons.circle_outlined,
                color: s.id == sets.active ? accent : null,
              ),
              title: Text(s.name, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [
                  for (final r in widget.catalog.routesAt(s.routes))
                    widget.catalog.routes[r].short,
                ].join(' · '),
                overflow: TextOverflow.ellipsis,
              ),
              selected: s.id == sets.active,
              onTap: () => widget.onActivate(s),
              onLongPress: () => manage(
                context,
                onRename: () => _renameSet(s),
                onDelete: () => widget.onDelete(s),
              ),
            ),
        ],
      ),
      _Hint(txt.holdToManage),
    ];
  }
}

/// [to] is where the row lands once it has been lifted out, which is what
/// `onReorderItem` already accounts for.
List<T> _moved<T>(List<T> list, int from, int to) {
  final next = [...list];
  next.insert(to, next.removeAt(from));
  return next;
}

/// A line of help under or instead of a list.
class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(text, style: material.Theme.of(context).textTheme.bodySmall),
    ),
  );
}

class _StopTile extends StatelessWidget {
  const _StopTile({
    super.key,
    required this.index,
    required this.catalog,
    required this.stop,
    required this.arrivals,
    required this.onUnpin,
    required this.onOpen,
    required this.watching,
    required this.onWatch,
    required this.onLine,
  });

  final int index;
  final Catalog catalog;
  final int stop;
  final List<Arrival> arrivals;
  final VoidCallback onUnpin;
  final VoidCallback onOpen;
  final Set<int> watching;
  final void Function(int route) onWatch;
  final void Function(int route) onLine;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.push_pin),
    // The handle sits beside the name rather than as the tile's trailing, which
    // would narrow the chips under it to one a row on a phone
    title: Row(
      children: [
        Expanded(child: Text(catalog.stopName(stop))),
        ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle),
        ),
      ],
    ),
    subtitle: arrivals.isEmpty
        ? Text(txt.nothingDue)
        : Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final a in arrivals.take(_dueShown))
                Due(
                  route: catalog.routes[a.route],
                  arrival: a,
                  watched: watching.contains(a.route),
                  onWatch: () => onWatch(a.route),
                  onLine: () => onLine(a.route),
                ),
            ],
          ),
    onTap: onOpen,
    onLongPress: () => manage(
      context,
      onDelete: () async => onUnpin(),
      deleteLabel: txt.unpin,
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
    required this.onRename,
    required this.onDelete,
  });

  final int index;
  final IconData icon;
  final String title;
  final String under;
  final VoidCallback onTap;
  final Future<void> Function() onRename;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title, overflow: TextOverflow.ellipsis),
    subtitle: Text(under, overflow: TextOverflow.ellipsis),
    onTap: onTap,
    onLongPress: () => manage(context, onRename: onRename, onDelete: onDelete),
    trailing: ReorderableDragStartListener(
      index: index,
      child: const Icon(Icons.drag_handle),
    ),
  );
}
