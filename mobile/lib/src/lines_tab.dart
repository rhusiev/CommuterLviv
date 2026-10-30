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

/// What the map watches, in one row above the list - a box that watches every
/// route or none, the saved sets, and saving the routes ticked as one - kept
/// apart from the list of routes below, which its own filters only narrow.
/// Sets live on the server; the current ticks are local until saved as one.
/// Renaming and deleting a set is in the Mine tab.
class LinesTab extends StatefulWidget {
  const LinesTab({
    super.key,
    required this.api,
    required this.catalog,
    required this.sets,
    required this.picked,
    required this.onToggle,
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

  /// The widest a set's name is shown in the toolbar before it is cut short.
  static const _setNameWidth = 120.0;

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

  /// Every route watched, or none: either way no saved set is.
  Future<void> _pick(bool all) async {
    await widget.api.activateSet(null);
    if (mounted) {
      widget.onActivated(null, [
        if (all)
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
        _toolbar(context),
        if (_failed case final failed?)
          Text(
            failed,
            style: material.Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: material.Theme.of(context).colorScheme.error),
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
        ..._recent(context),
        const SizedBox(height: 12),
        if (_why() case final why?) _Note(why),
        _grid(),
      ],
    ),
  );

  /// Filters on the list alone, each on or off. Each keeps its icon either
  /// way; being on shows only in its colour.
  Widget _narrowing() => Wrap(
    spacing: 6,
    children: [
      FilterChip(
        avatar: const Icon(Icons.near_me_outlined),
        label: Text(txt.nearLines),
        showCheckmark: false,
        selected: _nearOnly,
        onSelected: _toggleNear,
      ),
      FilterChip(
        avatar: const Icon(Icons.check),
        label: Text(txt.onlyWatched),
        showCheckmark: false,
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

  /// What the map watches, in one row: a box that, as a mail client's
  /// select-all, watches every route when none is and none otherwise, how
  /// many are watched, the saved sets, and saving these as one.
  Widget _toolbar(BuildContext context) {
    final total = widget.catalog.routes.length;
    final n = widget.picked.length;
    final sets = widget.sets?.sets ?? const <RouteSet>[];
    return Row(
      children: [
        Tooltip(
          message: n == 0 ? txt.watchAll : txt.watchNone,
          child: Checkbox(
            tristate: true,
            value: n == 0 ? false : (n == total ? true : null),
            onChanged: (_) => _guard(() => _pick(n == 0)),
          ),
        ),
        Expanded(
          child: Text(
            txt.onMapOf(n, total),
            style: material.Theme.of(context).textTheme.labelLarge,
          ),
        ),
        if (sets.isNotEmpty) _setPicker(sets),
        _setMenu(),
      ],
    );
  }

  /// The saved sets, one of which may be what the map watches.
  Widget _setPicker(List<RouteSet> sets) {
    final active = widget.sets?.active;
    final name = sets.where((s) => s.id == active).firstOrNull?.name;
    return PopupMenuButton<RouteSet>(
      tooltip: txt.setsMenu,
      onSelected: (s) => _guard(() => _activate(s)),
      itemBuilder: (_) => [
        for (final s in sets)
          CheckedPopupMenuItem(
            value: s,
            checked: s.id == active,
            child: Text(s.name),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _setNameWidth),
              child: Text(
                name ?? txt.setsMenu,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  /// Saving the routes ticked as a new set, or into the set watched once they
  /// differ from it.
  Widget _setMenu() {
    final active = widget.sets?.sets
        .where((s) => s.id == widget.sets?.active)
        .firstOrNull;
    final ids = _ids;
    final changed =
        active != null &&
        (active.routes.length != ids.length ||
            !active.routes.toSet().containsAll(ids));
    return PopupMenuButton<Future<void> Function()>(
      onSelected: _guard,
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _save,
          enabled: widget.picked.isNotEmpty,
          child: Text(txt.saveAsSet),
        ),
        if (changed)
          PopupMenuItem(
            value: () => _update(active),
            child: Text(txt.updateSet(active.name)),
          ),
      ],
    );
  }

  /// The lines opened lately, as the chips the grid has.
  List<Widget> _recent(BuildContext context) {
    final recent = widget.catalog.routesAt(widget.recent).toList();
    if (recent.isEmpty) return const [];
    return [
      const SizedBox(height: 10),
      Text(
        txt.recentLines,
        style: material.Theme.of(context).textTheme.labelMedium,
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: _gap,
        runSpacing: 4,
        children: [
          for (final i in recent)
            RouteChip(
              route: widget.catalog.routes[i],
              watched: widget.picked.contains(i),
              onWatch: () => widget.onToggle(i),
              onLine: () => widget.onOpen(i),
            ),
        ],
      ),
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
    required this.onStop,
    required this.onBack,
    required this.folded,
    required this.onFold,
    this.departures = _noDepartures,
  });

  static Future<List<int>> _noDepartures(int route, int stop) async => [];

  final Catalog catalog;
  final Live live;
  final int route;

  /// The route's timetabled departures from a stop today, for its hours.
  final Future<List<int>> Function(int route, int stop) departures;

  /// Down to its title alone, so the map shows the line.
  final bool folded;
  final ValueChanged<bool> onFold;

  /// Each way the line runs; empty until the shapes are in.
  final List<Direction> ways;
  final int way;
  final void Function(int way) onWay;
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
                // Folded, the title opens it again, as a folded journey's
                // strip does
                Expanded(
                  child: InkWell(
                    onTap: folded ? () => onFold(false) : null,
                    borderRadius: BorderRadius.circular(controlRadius),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: kMinInteractiveDimension,
                      ),
                      child: Row(
                        children: [
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
                  ),
                ),
                // At the bottom, like the journey: down folds, up opens
                IconButton(
                  tooltip: folded ? txt.showStops : txt.hideStops,
                  onPressed: () => onFold(!folded),
                  icon: Icon(folded ? Icons.expand_less : Icons.expand_more),
                ),
              ],
            ),
          ),
          if (!folded) ..._body(context, shown),
        ],
      ),
    );
  }

  /// Below the title: when it runs, the way, and the stops in order.
  List<Widget> _body(BuildContext context, Direction? shown) {
    final theme = material.Theme.of(context);
    final from = shown?.stops.firstOrNull;
    return [
      if (from != null)
        LineHours(
          key: ValueKey((route, from)),
          load: () => departures(route, from),
        ),
      if (shown?.stops.lastOrNull case final last?)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Tooltip(
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
    ];
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

/// When a line runs and how often, as plain chips: nothing to tap. Shows
/// nothing until [load] answers, and nothing if it fails.
class LineHours extends StatefulWidget {
  const LineHours({super.key, required this.load});

  final Future<List<int>> Function() load;

  @override
  State<LineHours> createState() => _LineHoursState();
}

class _LineHoursState extends State<LineHours> {
  List<int> _dep = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_fetch());
  }

  Future<void> _fetch() async {
    try {
      final dep = await widget.load();
      if (mounted) setState(() => _dep = dep);
    } catch (_) {
      // without them the line is shown as before, its hours left out
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final h = lineHours(_dep, now);
    if (h == null) return const SizedBox.shrink();
    final style = material.Theme.of(context).textTheme.bodySmall;
    final chips = [
      txt.firstDeparture(clockTime(h.first)),
      txt.lastDeparture(clockTime(h.last)),
      if (h.every case final every?) txt.everyMinutes(spanMinutes(every)),
    ];
    return Tooltip(
      message: txt.lineHoursHint,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final c in chips)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: hair),
                  borderRadius: BorderRadius.circular(controlRadius),
                ),
                child: Text(c, style: style),
              ),
          ],
        ),
      ),
    );
  }
}
