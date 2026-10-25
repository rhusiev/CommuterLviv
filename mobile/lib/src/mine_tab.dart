/// Everything that is the account's own, in one list: the pinned stops with
/// what is due there, the saved places, the route sets, and last the account
/// itself. Each list goes up as a whole, so a rename is the same one write as a
/// reorder - which is what keeps a rename atomic, since the name is the
/// identity server-side.
library;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;

import 'due.dart';
import 'live.dart';
import 'models.dart';
import 'sheets.dart' show askName, manage;
import 'strings.dart';
import 'theme.dart';

/// How many arrivals a pinned stop shows at most.
const _dueShown = 6;

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
    final theme = material.Theme.of(context);
    final pins = widget.pins;
    final places = _places;
    final sets = widget.sets;
    // The bar and the tab pill float over this list, so the ends need clearance
    return CustomScrollView(
      slivers: [
        SliverPadding(padding: EdgeInsets.only(top: floatingTop(context))),
        _Line(txt.pinnedStops, theme.textTheme.labelLarge),
        if (pins.isEmpty)
          _Line(txt.pinAStop, theme.textTheme.bodySmall)
        else
          AnimatedBuilder(
            animation: widget.live,
            builder: (context, _) => SliverReorderableList(
              itemCount: pins.length,
              onReorderItem: (from, to) =>
                  widget.onPins(_moved(pins, from, to)),
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
        _Line(txt.places, theme.textTheme.labelLarge),
        if (places.isEmpty)
          _Line(txt.saveHow, theme.textTheme.bodySmall)
        else
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
                under:
                    '${p.at.latitude.toStringAsFixed(4)}, '
                    '${p.at.longitude.toStringAsFixed(4)}',
                onTap: () => widget.onPlace(p),
                onRename: () => _renamePlace(p),
                onDelete: () async => _putPlaces([
                  for (final q in places)
                    if (q.name != p.name) q,
                ]),
              );
            },
          ),
        _Line(txt.sets, theme.textTheme.labelLarge),
        if (sets == null || sets.sets.isEmpty)
          _Line(txt.noSets, theme.textTheme.bodySmall)
        else
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
        if (places.isNotEmpty || sets?.sets.isNotEmpty == true)
          _Line(txt.holdToManage, theme.textTheme.bodySmall),
        const SliverToBoxAdapter(child: Divider(height: 1)),
        SliverToBoxAdapter(
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(txt.account),
            subtitle: Text(widget.username, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onAccount,
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.only(bottom: floatingBottom(context)),
        ),
      ],
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
  const _Line(this.text, this.style);

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(text, style: style),
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
    leading: IconButton(
      onPressed: onUnpin,
      icon: const Icon(Icons.push_pin),
      tooltip: txt.unpin,
    ),
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
