/// The app proper: a map of the city, and the times at the stops you pinned.
///
/// One screen owns all the state the two tabs share - the catalog, the socket,
/// which routes are shown, which stops are pinned - because both tabs are views
/// of the same subscription. Nothing else in the app holds any of it: the tabs,
/// the card and the sheets are handed what they draw and call back when
/// somebody touches them, so this file is the only place the state changes.
library;

import 'dart:async';

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../main.dart' show tick;
import 'api.dart';
import 'here.dart';
import 'journey_panel.dart';
import 'live.dart';
import 'map_tab.dart';
import 'map_theme.dart';
import 'models.dart';
import 'server_dialog.dart';
import 'sheets.dart';
import 'stop_card.dart';
import 'stop_search.dart';
import 'theme.dart';
import 'times_tab.dart';
import 'vehicle_card.dart';
import 'vehicle_layer.dart' show badgeRadius, stopsZoom;
import 'strings.dart';

/// How far a tap may land from a stop and still count. A finger is wider than
/// the dot it is aiming at.
const _hitRadius = 22.0;

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.username,
    required this.onOut,
  });

  final Api api;
  final String username;
  final VoidCallback onOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _map = MapController();
  Live? _live;
  Catalog? _catalog;
  Sets? _sets;
  String? _error;

  final Set<int> _routes = {};
  List<int> _drawn = const [];
  List<int> _pins = const [];
  int? _stop;
  int _tab = 0;

  bool _planning = false;
  LatLng? _from;
  LatLng? _to;
  End? _picking;

  /// Which end of a journey is waiting for the phone's own position, when a
  /// fix has been asked for and has not arrived yet
  End? _wantHere;

  late final Here _here = Here(onFirstFix: (at) => _map.move(at, 16));

  late MapTheme _theme = themeById(widget.api.mapTheme);
  Style? _style;

  @override
  void initState() {
    super.initState();
    _load();
    _loadStyle();
    _here.addListener(_fixArrived);
  }

  @override
  void dispose() {
    _live?.dispose();
    _here.removeListener(_fixArrived);
    _here.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final catalog = await widget.api.catalog();
      final sets = await widget.api.sets();
      final active = sets.sets.where((s) => s.id == sets.active).firstOrNull;
      final live = Live(widget.api)..open();
      if (!mounted) {
        live.dispose();
        return;
      }
      setState(() {
        _catalog = catalog;
        _sets = sets;
        _live = live;
        _pins = _resolve(catalog, sets.pins);
        _routes
          ..clear()
          ..addAll(_indexes(catalog, active?.routes ?? const []));
      });
      _push();
      await _carryOldPins(catalog, sets.pins);
    } on ApiError catch (e) {
      if (e.unauthorised) {
        widget.onOut();
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    } on Exception {
      if (mounted) {
        setState(() => _error = txt.unreachable(widget.api.base));
      }
    }
  }

  Iterable<int> _indexes(Catalog catalog, List<String> ids) =>
      ids.map((id) => catalog.index[id]).whereType<int>();

  /// Pinned stops arrive as feed ids and are used as catalog positions. A stop
  /// the city has since dropped simply does not resolve.
  List<int> _resolve(Catalog catalog, List<String> ids) => [
    for (final id in ids) ?catalog.stopIndex[id],
  ];

  /// The pins this device kept before the server did. They were stored as
  /// catalog positions, so they are read against the catalog loaded now, sent
  /// up once, and the old key is dropped only once that has gone through - a
  /// failed sign-in day should not be what loses them.
  Future<void> _carryOldPins(Catalog catalog, List<String> mine) async {
    final old = widget.api.oldPins(widget.username);
    if (old == null) return;
    final ids = [
      for (final i in old)
        if (i >= 0 && i < catalog.stops.length) catalog.stops[i].id,
    ];
    if (mine.isEmpty && ids.isNotEmpty) {
      await widget.api.setPins(ids);
      if (mounted) {
        setState(() => _pins = _resolve(catalog, ids));
        _watch();
      }
    }
    await widget.api.forgetOldPins(widget.username);
  }

  /// Tell the socket what to send, and work out which stops are worth drawing.
  /// Both follow from the chosen routes, so they are computed in one place.
  void _push() {
    final catalog = _catalog;
    final live = _live;
    if (catalog == null || live == null) return;
    live.setRoutes(_routes.toList()..sort());
    final drawn = <int>[
      for (var i = 0; i < catalog.stops.length; i++)
        if (catalog.stops[i].routes.any(_routes.contains)) i,
    ];
    setState(() => _drawn = drawn);
    _watch();
  }

  /// The stops the server should send arrivals for: what is pinned, plus
  /// whatever card is open. The server caps the list, so pins win.
  void _watch() {
    _live?.setStops({..._pins, ?_stop}.toList());
  }

  Future<void> _loadStyle() async {
    final theme = _theme;
    try {
      final read = await StyleReader(uri: theme.styleUrl).read();
      // Every VersaTiles style parses to a theme whose id is `default`, and the
      // renderer caches the tile images it draws under that id: without a
      // distinct one, picking a second style silently reads back the first
      // style's pictures, from disk, for as long as the cache lives
      final style = Style(
        name: read.name,
        theme: read.theme.copyWith(id: theme.id),
        providers: read.providers,
        sprites: read.sprites,
        center: read.center,
        zoom: read.zoom,
      );
      if (mounted && _theme.id == theme.id) setState(() => _style = style);
    } on Exception {
      if (mounted) setState(() => _error = txt.noBasemap);
    }
  }

  Future<void> _setTheme(MapTheme theme) async {
    setState(() {
      _theme = theme;
      _style = null;
    });
    await widget.api.setMapTheme(theme.id);
    await _loadStyle();
  }

  void _toggleRoute(int route) {
    setState(
      () =>
          _routes.contains(route) ? _routes.remove(route) : _routes.add(route),
    );
    _push();
  }

  Future<void> _pin(int stop) async {
    final catalog = _catalog;
    if (catalog == null) return;
    final pins = [..._pins];
    pins.contains(stop) ? pins.remove(stop) : pins.add(stop);
    setState(() => _pins = pins);
    _watch();
    // Optimistic: a pin that failed to save is back at the next sign-in, and
    // that is better than a tap that waits on the network
    try {
      await widget.api.setPins([for (final i in pins) catalog.stops[i].id]);
    } on Exception {
      // nothing to say about it here; the times keep working either way
    }
  }

  void _openStop(int stop, {bool fly = false}) {
    setState(() => _stop = stop);
    _watch();
    if (fly) {
      final s = _catalog!.stops[stop];
      _map.move(
        LatLng(s.lat, s.lon),
        _map.camera.zoom < 15 ? 16 : _map.camera.zoom,
      );
    }
    showFloatingSheet<void>(
      context,
      (_) => StopCard(
        catalog: _catalog!,
        live: _live!,
        stop: stop,
        pinned: _pins.contains(stop),
        watching: _routes,
        onPin: () => _pin(stop),
        onRoute: (route) {
          Navigator.pop(context);
          _toggleRoute(route);
        },
      ),
    ).whenComplete(() {
      if (!mounted) return;
      setState(() => _stop = null);
      _watch();
    });
  }

  void _tap(LatLng point) {
    final catalog = _catalog;
    if (catalog == null) return;
    // While an end of a journey is being set, every tap is that point: the
    // nearest stop is not what was asked for, and a door is rarely one
    if (_picking != null) {
      tick();
      setState(() {
        _at(_picking!, point);
        _picking = null;
      });
      return;
    }
    final camera = _map.camera;
    final at = camera.latLngToScreenOffset(point);

    // Vehicles first: they are drawn over the stops and are the larger target,
    // so a tap that lands on a badge meant the badge. They are also worth
    // tapping at any zoom, which is why this is above the stops' cutoff
    final live = _live;
    if (live != null) {
      var veh = -1;
      var near = badgeRadius * badgeRadius;
      final now = live.nowMs;
      for (final entry in live.vehicles.entries) {
        final p = sample(entry.value, now);
        final d = (camera.latLngToScreenOffset(LatLng(p.lat, p.lon)) - at)
            .distanceSquared;
        if (d < near) {
          near = d;
          veh = entry.key;
        }
      }
      if (veh >= 0) {
        tick();
        _openVehicle(veh);
        return;
      }
    }

    if (camera.zoom < stopsZoom) return;
    var best = -1;
    var closest = _hitRadius * _hitRadius;
    for (final i in _drawn) {
      final s = catalog.stops[i];
      final d = (camera.latLngToScreenOffset(LatLng(s.lat, s.lon)) - at)
          .distanceSquared;
      if (d < closest) {
        best = i;
        closest = d;
      }
    }
    if (best < 0) return;
    tick();
    _openStop(best);
  }

  void _openVehicle(int veh) {
    showFloatingSheet<void>(
      context,
      (_) => VehicleCard(
        api: widget.api,
        catalog: _catalog!,
        veh: veh,
        onStop: (stop) {
          Navigator.pop(context);
          _openStop(stop, fly: true);
        },
      ),
    );
  }

  /// The phone's own position, for one end of a journey. `Here` answers at
  /// once if it already has a fix and otherwise when the first one lands, so
  /// the end being waited for is remembered rather than the answer waited on.
  Future<void> _hereFor(End which) async {
    final at = await _here.start();
    if (!mounted) return;
    if (at == null && _here.state == Locating.denied) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(txt.noLocation)));
      return;
    }
    setState(() {
      if (at == null) {
        _wantHere = which;
      } else {
        _at(which, at);
      }
    });
  }

  void _fixArrived() {
    final which = _wantHere;
    final at = _here.fix?.point;
    if (which == null || at == null) return;
    setState(() {
      _at(which, at);
      _wantHere = null;
    });
  }

  void _at(End which, LatLng at) {
    if (which == End.from) {
      _from = at;
    } else {
      _to = at;
    }
  }

  Future<void> _search() async {
    final catalog = _catalog;
    if (catalog == null) return;
    final stop = await showSearch<int?>(
      context: context,
      delegate: StopSearch(catalog),
    );
    if (stop != null && mounted) {
      setState(() => _tab = 0);
      _openStop(stop, fly: true);
    }
  }

  Future<void> _menu(String choice) async {
    switch (choice) {
      case 'map':
        showFloatingSheet<void>(
          context,
          (_) => ThemeSheet(current: _theme, onPick: _setTheme),
        );
      case 'lang':
        showFloatingSheet<void>(context, (_) => LanguageSheet(api: widget.api));
      case 'server':
        // The session belonged to the old address and is gone with it, so a
        // change lands back on the sign-in screen rather than on a dead map
        if (await editServer(context, widget.api) && mounted) widget.onOut();
      case 'out':
        await _signOut();
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.api.logout();
    } on Exception {
      // A session the server has already forgotten is still a session gone
    }
    widget.onOut();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    final live = _live;
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('CommuterLviv')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: () => setState(() {
                  _error = null;
                  _load();
                  _loadStyle();
                }),
                child: Text(txt.tryAgain),
              ),
            ],
          ),
        ),
      );
    }
    if (catalog == null || live == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    // No app bar and no navigation bar: the map is the whole screen and the
    // chrome floats on top of it, which is why every piece below is placed in
    // the stack with its own inset rather than given a slot by the scaffold
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _tab,
            children: [
              MapTab(
                map: _map,
                style: _style,
                catalog: catalog,
                live: live,
                stops: _drawn,
                selected: _stop,
                theme: _theme,
                here: _here,
                empty: _routes.isEmpty,
                marks: [
                  if (_from != null) (at: _from!, label: 'A'),
                  if (_to != null) (at: _to!, label: 'B'),
                ],
                onTap: _tap,
              ),
              TimesTab(
                catalog: catalog,
                live: live,
                pins: _pins,
                onUnpin: _pin,
                onOpen: (stop) {
                  setState(() => _tab = 0);
                  _openStop(stop, fly: true);
                },
              ),
            ],
          ),
          if (_planning && _tab == 0)
            Positioned(
              left: floatingGap,
              right: floatingGap,
              bottom: floatingBottom(context),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                ),
                child: JourneyPanel(
                  api: widget.api,
                  catalog: catalog,
                  from: _from,
                  to: _to,
                  picking: _picking,
                  onPick: (which) => setState(() => _picking = which),
                  onSwap: () => setState(() {
                    final was = _from;
                    _from = _to;
                    _to = was;
                  }),
                  onHere: _hereFor,
                  onStop: (stop) => _openStop(stop, fly: true),
                  onClose: () => setState(() {
                    _planning = false;
                    _picking = null;
                  }),
                ),
              ),
            ),
          Positioned(
            left: floatingGap,
            right: floatingGap,
            top: MediaQuery.paddingOf(context).top + floatingGap,
            child: _TopBar(
              onSearch: _search,
              onRoutes: () => _openRoutes(catalog),
              onMenu: _menu,
              server: widget.api.base,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.paddingOf(context).bottom + floatingGap,
            child: Center(
              child: _Tabs(selected: _planning ? 2 : _tab, onPick: _pickTab),
            ),
          ),
          _Status(live: live),
        ],
      ),
    );
  }

  void _pickTab(int i) => setState(() {
    _tab = i == 1 ? 1 : 0;
    _planning = i == 2;
    if (!_planning) _picking = null;
  });

  void _openRoutes(Catalog catalog) => showFloatingSheet<void>(
    context,
    (_) => RouteSheet(
      api: widget.api,
      catalog: catalog,
      sets: _sets,
      picked: _routes,
      onToggle: _toggleRoute,
      onClear: () {
        setState(_routes.clear);
        _push();
      },
      onActivated: (set, routes) => setState(() {
        _routes
          ..clear()
          ..addAll(routes);
        _sets = Sets(sets: _sets!.sets, active: set.id, pins: _sets!.pins);
        _push();
      }),
      onSets: (sets) => setState(() => _sets = sets),
    ),
    scrollControlled: true,
  );
}

/// What used to be the app bar: a search pill wide enough to read, and the two
/// buttons that open everything else. It floats clear of the top edge, so the
/// map runs behind it and under the status bar.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onSearch,
    required this.onRoutes,
    required this.onMenu,
    required this.server,
  });

  final VoidCallback onSearch;
  final VoidCallback onRoutes;
  final void Function(String choice) onMenu;
  final String server;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Material(
          color: panel.withValues(alpha: 0.9),
          surfaceTintColor: Colors.transparent,
          shape: const StadiumBorder(side: BorderSide(color: hair)),
          elevation: 2,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onSearch,
            child: SizedBox(
              height: topBarHeight,
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  const Icon(Icons.search, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      txt.findStop,
                      overflow: TextOverflow.ellipsis,
                      style: material.Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: Colors.white54),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      RoundButton(
        tooltip: txt.routes,
        onPressed: onRoutes,
        child: const Icon(Icons.route_outlined),
      ),
      const SizedBox(width: 8),
      Material(
        color: panel.withValues(alpha: 0.9),
        surfaceTintColor: Colors.transparent,
        shape: const CircleBorder(side: BorderSide(color: hair)),
        elevation: 2,
        child: PopupMenuButton<String>(
          onSelected: onMenu,
          itemBuilder: (_) => [
            PopupMenuItem(value: 'map', child: Text(txt.mapStyle)),
            PopupMenuItem(value: 'lang', child: Text(txt.language)),
            PopupMenuItem(
              value: 'server',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(txt.server),
                subtitle: Text(server),
              ),
            ),
            PopupMenuItem(value: 'out', child: Text(txt.signOut)),
          ],
        ),
      ),
    ],
  );
}

/// Map, times and the planner, as one pill where a thumb is. The planner is a
/// third choice rather than a toggle in the bar because that is what it is: a
/// third thing to be looking at, over the same city.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.selected, required this.onPick});

  final int selected;
  final void Function(int index) onPick;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (Icons.map_outlined, txt.map),
      (Icons.schedule_outlined, txt.times),
      (Icons.directions_outlined, txt.plan),
    ];
    return Material(
      color: panel.withValues(alpha: 0.9),
      surfaceTintColor: Colors.transparent,
      shape: const StadiumBorder(side: BorderSide(color: hair)),
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: tabBarHeight,
        // Three equal columns, each as wide as the widest tab: `IntrinsicWidth`
        // over flexible children asks the row for the widest child per flex
        // unit, so the bar is still only as wide as it needs to be
        child: IntrinsicWidth(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, tab) in tabs.indexed)
                Expanded(
                  child: _Tab(
                    icon: tab.$1,
                    label: tab.$2,
                    on: i == selected,
                    onTap: () => onPick(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: on ? accent.withValues(alpha: 0.15) : null,
          borderRadius: BorderRadius.circular(tabBarHeight),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: on ? accent : Colors.white70),
              const SizedBox(width: 6),
              Text(
                label,
                // One weight whichever tab is on: a heavier label is a wider
                // label, and the other two tabs would slide as you switch
                style: TextStyle(
                  color: on ? accent : Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A two-pixel line along the very top of the screen, red while the socket is
/// away. Anything larger would be a banner about a state that is usually over
/// in a second, and it sits above the bar rather than under it because there is
/// no bar to sit under any more.
class _Status extends StatelessWidget {
  const _Status({required this.live});

  final Live live;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: live,
    builder: (context, _) => live.connection == Connection.live
        ? const SizedBox.shrink()
        : Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(
              minHeight: 2,
              color: material.Theme.of(context).colorScheme.error,
            ),
          ),
  );
}
