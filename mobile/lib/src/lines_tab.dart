/// The Lines tab: every route, to watch or to open one line of, and the one
/// line open, over the map.
library;

import 'dart:async' show unawaited;
import 'dart:math' show max;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;

import 'api.dart';
import 'eta.dart';
import 'here.dart';
import 'lines.dart';
import 'live.dart';
import 'models.dart';
import 'route_badge.dart';
import 'route_chip.dart';
import 'sheets.dart' show askName;
import 'strings.dart';
import 'theme.dart';

/// What the map watches - every route, a saved set, or the routes ticked by
/// hand - kept apart from the list of routes below, which its own filters only
/// narrow. Sets live on the server; the current ticks are local until saved as
/// one. Renaming and deleting a set is in the Mine tab.
class LinesTab extends StatefulWidget {
  const LinesTab({
    super.key,
    required this.api,
    required this.catalog,
    required this.sets,
    required this.picked,
    required this.onToggle,
    required this.onClear,
    required this.onActivated,
    required this.onSets,
    required this.onOpen,
    required this.recent,
    required this.here,
  });

  final Api api;
  final Catalog catalog;
  final Sets? sets;

  /// Route positions, the screen's own live set.
  final Set<int> picked;
  final void Function(int route) onToggle;
  final VoidCallback onClear;

  /// The set now watched, or null for every route, which is no saved set.
  final void Function(RouteSet? set, Iterable<int> routes) onActivated;

  final void Function(Sets sets) onSets;

  /// The line, from a chip's `›` or a recently opened row.
  final void Function(int route) onOpen;

  /// Route ids of the lines opened lately, latest first.
  final List<String> recent;

  /// Asked for a fix only once "Near me" is turned on.
  final Here here;

  @override
  State<LinesTab> createState() => _LinesTabState();
}

class _LinesTabState extends State<LinesTab> {
  /// The narrowest a route chip may be, and the space between two.
  static const _cell = 100.0;
  static const _gap = 6.0;

  String _query = '';
  bool _nearOnly = false;
  bool _watchedOnly = false;

  /// Why the last change to the sets did not go through
  String? _failed;

  List<String> get _ids => [
    for (final i in widget.picked) widget.catalog.routes[i].id,
  ];

  /// Runs [change], saying under the buttons why it failed if it does.
  Future<void> _guard(Future<void> Function() change) async {
    setState(() => _failed = null);
    try {
      await change();
    } on Exception catch (e) {
      if (mounted) setState(() => _failed = widget.api.failure(e));
    }
  }

  Future<void> _reload() async {
    final sets = await widget.api.sets();
    if (mounted) widget.onSets(sets);
  }

  Future<void> _save() async {
    final name = await askName(context, txt.nameSet);
    if (name == null || name.isEmpty) return;
    final made = await widget.api.createSet(name, _ids);
    try {
      await widget.api.activateSet(made.id);
    } finally {
      // made, the set belongs in the list even if it could not be activated
      if (mounted) await _reload();
    }
  }

  Future<void> _update(RouteSet set) async {
    await widget.api.updateSet(set.id, set.name, _ids);
    await _reload();
  }

  Future<void> _activate(RouteSet set) async {
    await widget.api.activateSet(set.id);
    if (mounted) {
      widget.onActivated(set, widget.catalog.routesAt(set.routes));
    }
  }

  Future<void> _pickAll() async {
    await widget.api.activateSet(null);
    if (mounted) {
      widget.onActivated(null, [
        for (var i = 0; i < widget.catalog.routes.length; i++) i,
      ]);
    }
  }

  void _toggleNear(bool on) {
    setState(() => _nearOnly = on);
    if (on) unawaited(widget.here.start());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.here,
    builder: (context, _) => ListView(
      // The bar and the tab pill float over this list, so the ends need
      // clearance
      padding: EdgeInsets.fromLTRB(
        16,
        floatingTop(context),
        16,
        floatingBottom(context),
      ),
      children: [
        ..._watched(context),
        _actions(),
        if (_failed case final failed?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              failed,
              style: material.Theme.of(context).textTheme.bodySmall?.copyWith(
                color: material.Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ..._recentRows(context),
        Text(
          txt.routes,
          style: material.Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: txt.filterRoutes,
          ),
        ),
        const SizedBox(height: 6),
        _narrowing(),
        const SizedBox(height: 12),
        if (_why() case final why?) _Note(why),
        _grid(),
      ],
    ),
  );

  /// Filters on the list alone, each on or off: filter chips with a tick, so
  /// they do not read as one of the choices of what the map watches.
  Widget _narrowing() => Wrap(
    spacing: 6,
    children: [
      FilterChip(
        avatar: _nearOnly ? null : const Icon(Icons.near_me_outlined),
        label: Text(txt.nearLines),
        selected: _nearOnly,
        onSelected: _toggleNear,
      ),
      FilterChip(
        label: Text(txt.onlyWatched),
        selected: _watchedOnly,
        onSelected: (on) => setState(() => _watchedOnly = on),
      ),
    ],
  );

  /// The nearby routes once there is a fix; null while there is none.
  Set<int>? get _near => switch (widget.here.fix?.point) {
    final at? => routesNear(widget.catalog, at, nearLinesM),
    null => null,
  };

  /// What stands in for routes the filters leave out, if anything does.
  String? _why() => _nearOnly
      ? _nearWhy()
      : _watchedOnly && widget.picked.isEmpty
      ? txt.noneWatched
      : null;

  String? _nearWhy() {
    if (widget.here.state == Locating.denied) return txt.noLocation;
    final near = _near;
    if (near == null) return txt.locating;
    return near.isEmpty ? txt.nothingNearLines(nearLinesM) : null;
  }

  /// What the map watches: every route, one of the saved sets, or the routes
  /// ticked below. A set is the selection at the moment it was saved.
  List<Widget> _watched(BuildContext context) {
    final sets = widget.sets?.sets ?? const <RouteSet>[];
    final active = widget.sets?.active;
    final all =
        widget.catalog.routes.isNotEmpty &&
        widget.picked.length == widget.catalog.routes.length;
    final style = material.Theme.of(context).textTheme;
    return [
      Text.rich(
        TextSpan(
          text: txt.onMap,
          children: [
            TextSpan(
              text: '  ${txt.routesOn(widget.picked.length)}',
              style: style.bodySmall,
            ),
          ],
        ),
        style: style.labelLarge,
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        children: [
          ChoiceChip(
            label: Text(txt.allRoutes),
            showCheckmark: false,
            selected: all && sets.every((s) => s.id != active),
            onSelected: (_) => _guard(_pickAll),
          ),
          for (final s in sets)
            ChoiceChip(
              label: Text(s.name),
              // A checkmark widens the chip, shuffling the ones after it
              showCheckmark: false,
              selected: s.id == active,
              onSelected: (_) => _guard(() => _activate(s)),
            ),
        ],
      ),
    ];
  }

  List<Widget> _recentRows(BuildContext context) {
    final recent = widget.catalog.routesAt(widget.recent).toList();
    return [
      const Divider(height: 24),
      if (recent.isNotEmpty) ...[
        Text(
          txt.recentLines,
          style: material.Theme.of(context).textTheme.labelLarge,
        ),
        for (final i in recent)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: RouteBadge(route: widget.catalog.routes[i]),
            title: Text(
              widget.catalog.routes[i].long,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => widget.onOpen(i),
          ),
        const SizedBox(height: 12),
      ],
    ];
  }

  /// Grouped by vehicle type, in catalog order: tram 1 and bus 1 are
  /// different lines that would otherwise sit in one undivided grid
  Map<String, List<int>> _groups() {
    final catalog = widget.catalog;
    final needle = _query.toLowerCase();
    final near = _nearOnly ? (_near ?? const {}) : null;
    final groups = <String, List<int>>{};
    for (var i = 0; i < catalog.routes.length; i++) {
      final r = catalog.routes[i];
      if (_watchedOnly && !widget.picked.contains(i)) continue;
      if (near != null && !near.contains(i)) continue;
      if (needle.isEmpty ||
          r.short.toLowerCase().contains(needle) ||
          r.long.toLowerCase().contains(needle)) {
        groups.putIfAbsent(r.type, () => []).add(i);
      }
    }
    return groups;
  }

  Widget _grid() => LayoutBuilder(
    builder: (context, box) {
      // Equal cells, as many as fit, so the grid has straight edges whatever
      // a route is called
      final cols = max(1, ((box.maxWidth + _gap) / (_cell + _gap)).floor());
      final width = (box.maxWidth - _gap * (cols - 1)) / cols;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final MapEntry(key: type, value: shown) in _groups().entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    container: true,
                    header: true,
                    child: Text(
                      txt.kinds[type] ?? type,
                      style: material.Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: _gap,
                    runSpacing: 4,
                    children: [for (final i in shown) _chip(i, width)],
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );

  Widget _chip(int i, double width) => RouteChip(
    route: widget.catalog.routes[i],
    watched: widget.picked.contains(i),
    width: width,
    onWatch: () => widget.onToggle(i),
    onLine: () => widget.onOpen(i),
  );

  Widget _actions() {
    final active = widget.sets?.sets
        .where((s) => s.id == widget.sets?.active)
        .firstOrNull;
    final ids = _ids;
    final changed =
        active != null &&
        (active.routes.length != ids.length ||
            !active.routes.toSet().containsAll(ids));
    return Row(
      children: [
        IconButton(
          onPressed: widget.picked.isEmpty ? null : widget.onClear,
          icon: const Icon(Icons.clear_all),
          tooltip: txt.clear,
        ),
        const SizedBox(width: 8),
        if (changed) ...[
          Expanded(
            child: FilledButton.tonal(
              onPressed: () => _guard(() => _update(active)),
              child: Text(
                txt.updateSet(active.name),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: FilledButton.tonal(
            onPressed: widget.picked.isEmpty ? null : () => _guard(_save),
            child: Text(txt.saveAsSet, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: material.Theme.of(context).textTheme.bodySmall),
  );
}

/// One line, over the map: its stops one way, with what this route has due at
/// each and where its vehicles are.
class LinePanel extends StatelessWidget {
  const LinePanel({
    super.key,
    required this.catalog,
    required this.live,
    required this.route,
    required this.ways,
    required this.way,
    required this.onWay,
    required this.watching,
    required this.onWatch,
    required this.onStop,
    required this.onBack,
  });

  final Catalog catalog;
  final Live live;
  final int route;

  /// Each way the line runs; empty until the shapes are in.
  final List<Direction> ways;
  final int way;
  final void Function(int way) onWay;
  final bool watching;
  final VoidCallback onWatch;
  final void Function(int stop) onStop;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = material.Theme.of(context);
    final line = catalog.routes[route];
    final shown = ways.elementAtOrNull(way);
    return Material(
      elevation: 8,
      color: panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(panelRadius),
        side: const BorderSide(color: hair),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
                RouteBadge(route: line),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    line.long,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // All the width Watch leaves, not the half a Flexible beside a
                // Spacer gets; the chip itself is only as wide as its name
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: switch (shown?.stops.lastOrNull) {
                      final last? => Tooltip(
                        message: txt.otherWay,
                        child: ActionChip(
                          label: Text(
                            '→ ${catalog.stops[last].name}',
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: ways.length < 2
                              ? null
                              : () => onWay((way + 1) % ways.length),
                        ),
                      ),
                      null => const SizedBox.shrink(),
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(txt.watchLine),
                  selected: watching,
                  onSelected: (_) => onWatch(),
                ),
              ],
            ),
          ),
          if (ways.isNotEmpty && (shown?.stops.isEmpty ?? true))
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(txt.noLineStops, style: theme.textTheme.bodySmall),
            ),
          if (shown != null)
            Flexible(
              child: AnimatedBuilder(
                animation: live,
                builder: (context, _) => _rows(shown.stops),
              ),
            ),
        ],
      ),
    );
  }

  Widget _rows(List<int> stops) {
    final rows = lineRows(stops, live.arrivals, route);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        for (final (:stop, :next, :vehs) in rows)
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: SizedBox(
              width: 24,
              child: vehs.isEmpty
                  ? const Icon(Icons.circle, size: 6, color: Colors.white38)
                  : Icon(
                      Icons.directions_bus,
                      size: 18,
                      color: accent,
                      semanticLabel: txt.vehicleHere,
                    ),
            ),
            title: Text(
              catalog.stops[stop].name,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: next == null
                ? null
                : Text(
                    countdown(next.t),
                    style: TextStyle(
                      color: next.planned ? Colors.white38 : null,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
            onTap: () => onStop(stop),
          ),
      ],
    );
  }
}
