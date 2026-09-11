/// The sheets the top bar opens, and [showFloatingSheet] that puts every sheet
/// in the app on screen.
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

/// A sheet that floats rather than docks. `showModalBottomSheet` is docked by
/// construction, so the sheet itself is transparent and the gap is padding
/// inside it; the handle is drawn here for the same reason. The bottom inset is
/// only [floatingGap] because each sheet's own `SafeArea` clears the system bar.
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

/// Routes, and the saved sets of routes. Sets live on the server; the current
/// ticks are local until saved as one.
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

  /// Route positions, the screen's own live set.
  final Set<int> picked;
  final void Function(int route) onToggle;
  final VoidCallback onClear;

  final void Function(RouteSet set, Iterable<int> routes) onActivated;

  final void Function(Sets sets) onSets;

  /// The line, opened by a long press: a tap already toggles the route.
  final void Function(int route) onRoute;

  @override
  State<RouteSheet> createState() => _RouteSheetState();
}

class _RouteSheetState extends State<RouteSheet> {
  String _filter = '';

  /// The sheet is its own route, built once, so later `sets` never reach it.
  late String? _active = widget.sets?.active;
  late List<RouteSet> _sets = widget.sets?.sets ?? const [];

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
    widget.onActivated(set, widget.catalog.routesAt(set.routes));
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
                      // A checkmark widens the chip, shuffling the ones after it
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
                    // No tooltip: a chip's own tooltip fires on long press and
                    // wins the gesture arena, so the line would never open
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
