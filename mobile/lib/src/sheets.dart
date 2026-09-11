/// What the top bar opens: which routes are on the map, which basemap they are
/// drawn on, and which language everything is said in.
///
/// [showFloatingSheet] is how every sheet in the app is put on screen, so a
/// card that rises out of the map matches the cards already on it.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;

import 'api.dart';
import 'map_theme.dart';
import 'models.dart';
import 'route_badge.dart';
import 'strings.dart';
import 'theme.dart';

/// A sheet that floats rather than docks: rounded on all four corners and
/// standing off all three edges.
///
/// `showModalBottomSheet` is docked by construction, so the gap is padding
/// inside a sheet that is itself transparent. The drag handle is drawn here for
/// the same reason - the framework's own would land on the transparent surface,
/// above the card instead of on it. The bottom is only [floatingGap] because
/// each sheet's own `SafeArea` is what clears the system bar.
Future<T?> showFloatingSheet<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool scrollControlled = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: scrollControlled,
  backgroundColor: Colors.transparent,
  builder: (context) => Padding(
    padding: const EdgeInsets.all(floatingGap),
    child: Material(
      color: panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(panelRadius),
        side: const BorderSide(color: hair),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _Handle(),
          Flexible(child: builder(context)),
        ],
      ),
    ),
  ),
);

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => Container(
    width: 32,
    height: 4,
    margin: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white24,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

class ThemeSheet extends StatelessWidget {
  const ThemeSheet({super.key, required this.current, required this.onPick});

  final MapTheme current;
  final void Function(MapTheme theme) onPick;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final t in mapThemes)
          ListTile(
            onTap: () {
              Navigator.pop(context);
              onPick(t);
            },
            title: Text(t.name),
            subtitle: Text(t.dark ? txt.dark : txt.light),
            trailing: t.id == current.id ? const Icon(Icons.check) : null,
          ),
      ],
    ),
  );
}

/// Ukrainian or English. Applied at once - `useLang` rebuilds the tree from the
/// root - and stored afterwards, because writing to the phone's preferences is
/// slower than a frame and nothing waits on it.
class LanguageSheet extends StatelessWidget {
  const LanguageSheet({super.key, required this.api});

  final Api api;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final l in Lang.values)
          ListTile(
            onTap: () {
              useLang(l);
              Navigator.pop(context);
              unawaited(api.setLanguage(l.name));
            },
            title: Text(l == Lang.uk ? 'Українська' : 'English'),
            trailing: l == lang ? const Icon(Icons.check) : null,
          ),
      ],
    ),
  );
}

/// Routes, and the saved sets of routes. Sets live on the server so the phone
/// and the browser show the same thing; which routes are ticked right now is
/// only ticked here until it is saved as one.
class RouteSheet extends StatefulWidget {
  const RouteSheet({
    super.key,
    required this.api,
    required this.catalog,
    required this.sets,
    required this.picked,
    required this.onToggle,
    required this.onClear,
    required this.onActivated,
    required this.onSets,
    required this.onRoute,
  });

  final Api api;
  final Catalog catalog;
  final Sets? sets;

  /// Route positions, the screen's own live set - ticking a chip changes what
  /// the map shows before anything is saved
  final Set<int> picked;
  final void Function(int route) onToggle;
  final VoidCallback onClear;

  /// A set was chosen: these are the routes it names, as positions
  final void Function(RouteSet set, Iterable<int> routes) onActivated;

  /// The server's list of sets changed, and this is it
  final void Function(Sets sets) onSets;

  /// A route's line was asked for. A tap here means show it on the map, which
  /// is what this sheet is for, so the line is on the long press instead
  final void Function(int route) onRoute;

  @override
  State<RouteSheet> createState() => _RouteSheetState();
}

class _RouteSheetState extends State<RouteSheet> {
  String _filter = '';

  /// Which set is showing. The sheet is a route of its own, built once from
  /// whatever `sets` was then, so the screen's later value never reaches it -
  /// which is why the highlight used to stay on the set chosen before this one
  late String? _active = widget.sets?.active;
  late List<RouteSet> _sets = widget.sets?.sets ?? const [];

  Iterable<int> _positions(List<String> ids) =>
      ids.map((id) => widget.catalog.index[id]).whereType<int>();

  List<String> get _ids =>
      [for (final i in widget.picked) widget.catalog.routes[i].id];

  Future<String?> _ask(String title, [String? was]) => showDialog<String>(
    context: context,
    builder: (context) {
      final field = TextEditingController(text: was);
      return AlertDialog.adaptive(
        title: Text(title),
        content: TextField(controller: field, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(txt.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, field.text.trim()),
            child: Text(txt.save),
          ),
        ],
      );
    },
  );

  /// Whatever the server now holds, into both this sheet and the screen behind
  /// it
  Future<void> _reload() async {
    final sets = await widget.api.sets();
    if (!mounted) return;
    widget.onSets(sets);
    setState(() => _sets = sets.sets);
  }

  Future<void> _save() async {
    final name = await _ask(txt.nameSet);
    if (name == null || name.isEmpty) return;
    final made = await widget.api.createSet(name, _ids);
    await widget.api.activateSet(made.id);
    if (!mounted) return;
    _active = made.id;
    await _reload();
  }

  /// The picked routes, into the set that is showing. The name is left alone -
  /// this is the set being what is on the map now, not a different set
  Future<void> _update(RouteSet set) async {
    await widget.api.updateSet(set.id, set.name, _ids);
    await _reload();
  }

  Future<void> _rename(RouteSet set) async {
    final name = await _ask(txt.renameSet, set.name);
    if (name == null || name.isEmpty || name == set.name) return;
    await widget.api.updateSet(set.id, name, set.routes);
    await _reload();
  }

  Future<void> _delete(RouteSet set) async {
    await widget.api.deleteSet(set.id);
    if (set.id == _active) _active = null;
    await _reload();
  }

  /// Rename or delete. Both are rare enough to live under a hold rather than
  /// take a button beside every chip
  Future<void> _manage(RouteSet set) async {
    final what = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text(txt.renameSet),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(txt.deleteSet),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (what == 'rename') await _rename(set);
    if (what == 'delete') await _delete(set);
  }

  Future<void> _activate(RouteSet set) async {
    await widget.api.activateSet(set.id);
    if (!mounted) return;
    widget.onActivated(set, _positions(set.routes));
    setState(() => _active = set.id);
  }

  @override
  Widget build(BuildContext context) {
    final catalog = widget.catalog;
    final needle = _filter.toLowerCase();
    final shown = [
      for (var i = 0; i < catalog.routes.length; i++)
        if (needle.isEmpty ||
            catalog.routes[i].short.toLowerCase().contains(needle) ||
            catalog.routes[i].long.toLowerCase().contains(needle))
          i,
    ];
    final sets = _sets;
    final active = sets.where((s) => s.id == _active).firstOrNull;
    // Only while the picks and the set disagree: a button that does nothing is
    // a button that has to be read before it can be ignored
    final changed = active != null &&
        (active.routes.length != _ids.length ||
            !active.routes.toSet().containsAll(_ids));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (sets.isNotEmpty) ...[
            Text(
              txt.sets,
              style: material.Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final s in sets)
                  GestureDetector(
                    onLongPress: () => _manage(s),
                    child: ChoiceChip(
                      label: Text(s.name),
                      // The colour says it is chosen. A checkmark says it too
                      // and widens the chip doing so, shuffling every chip
                      // after it
                      showCheckmark: false,
                      selected: s.id == _active,
                      onSelected: (_) => _activate(s),
                    ),
                  ),
              ],
            ),
            const Divider(height: 24),
          ],
          TextField(
            onChanged: (v) => setState(() => _filter = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: txt.filterRoutes,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final i in shown)
                GestureDetector(
                  onLongPress: () {
                    Navigator.pop(context);
                    widget.onRoute(i);
                  },
                  child: FilterChip(
                    label: RouteBadge(
                      route: catalog.routes[i],
                      muted: !widget.picked.contains(i),
                    ),
                    // No tooltip: a chip shows one on a long press, and it won
                    // the gesture, so the line never opened. The line view
                    // names the route anyway
                    showCheckmark: false,
                    selected: widget.picked.contains(i),
                    onSelected: (_) {
                      widget.onToggle(i);
                      setState(() {});
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Everywhere else a badge is the way to the line. Here a tap is
          // already taken, by the one thing this sheet exists to do
          Text(
            txt.holdForLine,
            style: material.Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: widget.picked.isEmpty
                    ? null
                    : () {
                        widget.onClear();
                        setState(() {});
                      },
                child: Text(txt.clear),
              ),
              const Spacer(),
              if (changed) ...[
                FilledButton.tonal(
                  onPressed: () => _update(active),
                  child: Text(txt.updateSet(active.name)),
                ),
                const SizedBox(width: 8),
              ],
              FilledButton.tonal(
                onPressed: widget.picked.isEmpty ? null : _save,
                child: Text(txt.saveAsSet),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
