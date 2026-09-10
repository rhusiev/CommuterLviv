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

  @override
  State<RouteSheet> createState() => _RouteSheetState();
}

class _RouteSheetState extends State<RouteSheet> {
  String _filter = '';

  Iterable<int> _positions(List<String> ids) =>
      ids.map((id) => widget.catalog.index[id]).whereType<int>();

  Future<void> _save() async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        final field = TextEditingController();
        return AlertDialog.adaptive(
          title: Text(txt.nameSet),
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
    if (name == null || name.isEmpty) return;
    final ids = [for (final i in widget.picked) widget.catalog.routes[i].id];
    final made = await widget.api.createSet(name, ids);
    await widget.api.activateSet(made.id);
    final sets = await widget.api.sets();
    if (!mounted) return;
    widget.onSets(sets);
    setState(() {});
  }

  Future<void> _activate(RouteSet set) async {
    await widget.api.activateSet(set.id);
    if (!mounted) return;
    widget.onActivated(set, _positions(set.routes));
    setState(() {});
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
    final sets = widget.sets?.sets ?? const <RouteSet>[];
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
                  ChoiceChip(
                    label: Text(s.name),
                    selected: s.id == widget.sets?.active,
                    onSelected: (_) => _activate(s),
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
                FilterChip(
                  label: RouteBadge(route: catalog.routes[i], muted: true),
                  tooltip: catalog.routes[i].long,
                  selected: widget.picked.contains(i),
                  onSelected: (_) {
                    widget.onToggle(i);
                    setState(() {});
                  },
                ),
            ],
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
