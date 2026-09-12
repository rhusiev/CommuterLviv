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

/// The one-field dialog behind every name in the app.
Future<String?> askName(
  BuildContext context,
  String title, {
  String? was,
  String? action,
}) => showDialog<String>(
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
          child: Text(action ?? txt.save),
        ),
      ],
    );
  },
);

/// What a long press on a saved thing offers. A thing that cannot be renamed -
/// a pinned stop wears the stop's own name - passes a null [onRename].
Future<void> manage(
  BuildContext context, {
  Future<void> Function()? onRename,
  required Future<void> Function() onDelete,
}) async {
  final what = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Wrap(
        children: [
          if (onRename != null)
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text(txt.rename),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(txt.delete),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (what == 'rename') await onRename!();
  if (what == 'delete') await onDelete();
}

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

/// Everything that changes what the map shows, in one place: the overlays as
/// switches, the basemap as a choice. Anything here is visible on the map the
/// moment it is touched, which is the rule for what belongs in this sheet
/// rather than behind the account button.
class LayersSheet extends StatefulWidget {
  const LayersSheet({
    super.key,
    required this.lines,
    required this.onLines,
    required this.traffic,
    required this.onTraffic,
    required this.theme,
    required this.onTheme,
  });

  final bool lines;
  final ValueChanged<bool> onLines;
  final bool traffic;
  final ValueChanged<bool> onTraffic;
  final MapTheme theme;
  final void Function(MapTheme theme) onTheme;

  @override
  State<LayersSheet> createState() => _LayersSheetState();
}

/// The sheet is its own route and the screen behind it never rebuilds it, so a
/// switch has to hold its own position while the map changes under the sheet.
class _LayersSheetState extends State<LayersSheet> {
  late bool _lines = widget.lines;
  late bool _traffic = widget.traffic;
  late MapTheme _theme = widget.theme;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.polyline_outlined),
            title: Text(txt.everyRoute),
            value: _lines,
            onChanged: (on) {
              setState(() => _lines = on);
              widget.onLines(on);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.traffic_outlined),
            title: Text(txt.traffic),
            value: _traffic,
            onChanged: (on) {
              setState(() => _traffic = on);
              widget.onTraffic(on);
            },
          ),
          const Divider(height: 1),
          _Label(txt.mapStyle),
          for (final t in mapThemes)
            ListTile(
              leading: Icon(
                t.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              ),
              title: Text(t.name),
              trailing: t.id == _theme.id ? const Icon(Icons.check) : null,
              onTap: () {
                setState(() => _theme = t);
                widget.onTheme(t);
              },
            ),
        ],
      ),
    ),
  );
}

/// Everything that belongs to the account rather than to the map, in the order
/// it is reached for: what was kept, then how the app is set up, then the way
/// out, set apart below a rule so it is never the tap next to anything else.
class AccountSheet extends StatelessWidget {
  const AccountSheet({
    super.key,
    required this.server,
    required this.onSaved,
    required this.onLanguage,
    required this.onServer,
    required this.onOut,
  });

  final String server;
  final VoidCallback onSaved;
  final VoidCallback onLanguage;
  final VoidCallback onServer;
  final VoidCallback onOut;

  @override
  Widget build(BuildContext context) {
    final colours = material.Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: Text(txt.saved),
            onTap: onSaved,
          ),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(txt.language),
            trailing: Text(lang == Lang.uk ? 'Українська' : 'English'),
            onTap: onLanguage,
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: Text(txt.server),
            subtitle: Text(server),
            onTap: onServer,
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.logout, color: colours.error),
            title: Text(txt.signOut, style: TextStyle(color: colours.error)),
            onTap: onOut,
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(text, style: material.Theme.of(context).textTheme.labelLarge),
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

  List<String> get _ids => [
    for (final i in widget.picked) widget.catalog.routes[i].id,
  ];

  Future<void> _reload() async {
    final sets = await widget.api.sets();
    if (!mounted) return;
    widget.onSets(sets);
    setState(() => _sets = sets.sets);
  }

  Future<void> _save() async {
    final name = await askName(context, txt.nameSet);
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
    final name = await askName(context, txt.rename, was: set.name);
    if (name == null || name.isEmpty || name == set.name) return;
    await widget.api.updateSet(set.id, name, set.routes);
    await _reload();
  }

  Future<void> _delete(RouteSet set) async {
    await widget.api.deleteSet(set.id);
    if (set.id == _active) _active = null;
    await _reload();
  }

  Future<void> _manage(RouteSet set) => manage(
    context,
    onRename: () => _rename(set),
    onDelete: () => _delete(set),
  );

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
    final changed =
        active != null &&
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
