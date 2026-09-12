/// The map, the times, and the only place the shared state changes.
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
import 'route_badge.dart';
import 'saved.dart';
import 'server_dialog.dart';
import 'sheets.dart';
import 'stop_card.dart';
import 'stop_search.dart';
import 'theme.dart';
import 'times_tab.dart';
import 'vehicle_card.dart';
import 'vehicle_layer.dart' show badgeRadius, stopsZoom;
import 'strings.dart';

/// How far a tap may land from a stop and still count.
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

  /// The route outlives its tab, so leaving and coming back keeps it.
  int? _route;
  bool _onRoute = false;
  bool _allLines = false;
  Shapes? _shapes;
  List<int> _drawn = const [];
  List<int> _pins = const [];
  int? _stop;
  int _tab = 0;

  /// Only while it is on does anything ask the server how the streets run.
  bool _traffic = false;

  bool _planning = false;
  LatLng? _from;
  LatLng? _to;
  End? _picking;

  /// Which end is waiting on a fix that has been asked for but not arrived.
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
        _pins = catalog.stopsAt(sets.pins);
        _routes
          ..clear()
          ..addAll(catalog.routesAt(active?.routes ?? const []));
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

  /// Sends this device's pre-server pins up once. The old key is dropped only
  /// after that has gone through.
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
        setState(() => _pins = catalog.stopsAt(ids));
        _watch();
      }
    }
    await widget.api.forgetOldPins(widget.username);
  }

  void _push() {
    final catalog = _catalog;
    final live = _live;
    if (catalog == null || live == null) return;
    final shown = _shown;
    live.setRoutes(shown.toList()..sort());
    final drawn = <int>[
      for (var i = 0; i < catalog.stops.length; i++)
        if (catalog.stops[i].routes.any(shown.contains)) i,
    ];
    setState(() => _drawn = drawn);
    _watch();
  }

  Set<int> get _shown => _onRoute && _route != null ? {_route!} : _routes;

  List<int> get _lines {
    if (_onRoute && _route != null) return [_route!];
    if (!_allLines) return const [];
    return [for (var i = 0; i < _catalog!.routes.length; i++) i];
  }

  /// Half a megabyte, so fetched lazily and only once.
  Future<void> _geometry() async {
    if (_shapes != null) return;
    try {
      final shapes = await widget.api.shapes();
      if (mounted) setState(() => _shapes = shapes);
    } on Exception {
      if (mounted) setState(() => _error = txt.unreachable(widget.api.base));
    }
  }

  List<Place> _withoutPlace(String name) => [
    for (final p in _sets?.places ?? const <Place>[])
      if (p.name != name) p,
  ];

  /// Kept by name, so saving over a name moves that place.
  Future<void> _savePlace(String name, LatLng at) =>
      _places([..._withoutPlace(name), Place(name: name, at: at)]);

  Future<void> _forgetPlace(String name) => _places(_withoutPlace(name));

  Future<void> _places(List<Place> next) async {
    final sets = _sets;
    if (sets == null) return;
    try {
      final saved = await widget.api.setPlaces(next);
      if (!mounted) return;
      setState(
        () => _sets = Sets(
          sets: sets.sets,
          active: sets.active,
          pins: sets.pins,
          places: saved,
        ),
      );
    } on Exception {
      if (mounted) setState(() => _error = txt.unreachable(widget.api.base));
    }
  }

  void _openRoute(int route) {
    setState(() {
      _route = route;
      _onRoute = true;
      _tab = 0;
      _planning = false;
    });
    _push();
    _geometry().then((_) {
      final shape = _shapes?.routes.elementAtOrNull(route);
      final points = [
        for (final line in shape?.lines ?? const <RouteLine>[]) ...line.pts,
      ];
      if (!mounted || points.isEmpty) return;
      _map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(40),
        ),
      );
    });
  }

  void _closeRoute() {
    setState(() {
      _route = null;
      _onRoute = false;
    });
    _push();
  }

  /// The server caps the watch list, so pins go first.
  void _watch() {
    _live?.setStops({..._pins, ?_stop}.toList());
  }

  Future<void> _loadStyle() async {
    final theme = _theme;
    try {
      final read = await StyleReader(uri: theme.styleUrl).read();
      // Every VersaTiles style parses with theme id `default`, and the renderer
      // caches tile images under that id, so each style needs a distinct one
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

  Future<void> _pin(int stop) {
    final pins = [..._pins];
    pins.contains(stop) ? pins.remove(stop) : pins.add(stop);
    return _savePins(pins);
  }

  Future<void> _savePins(List<int> pins) async {
    final catalog = _catalog;
    if (catalog == null) return;
    setState(() => _pins = pins);
    _watch();
    try {
      await widget.api.setPins([for (final i in pins) catalog.stops[i].id]);
    } on Exception {
      // Optimistic: a pin that failed to save is back at the next sign-in
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
        onLine: (route) {
          Navigator.pop(context);
          _openRoute(route);
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
    // While picking an end, a tap is that point, not the nearest stop
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

    // Vehicles first: drawn over the stops, and hit at any zoom
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
        onRoute: (route) {
          Navigator.pop(context);
          _openRoute(route);
        },
      ),
    );
  }

  /// `Here` answers at once with an existing fix, else when the first lands,
  /// so the waiting end is remembered rather than awaited.
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
    final hit = await showSearch<Hit?>(
      context: context,
      delegate: StopSearch(
        api: widget.api,
        catalog: catalog,
        onSave: _savePlace,
      ),
    );
    if (hit == null || !mounted) return;
    setState(() => _tab = 0);
    switch (hit) {
      case StopHit(:final stop):
        _openStop(stop, fly: true);
      case PlaceHit(:final at):
        _fly(at);
    }
  }

  void _fly(LatLng at) =>
      _map.move(at, _map.camera.zoom < 15 ? 16 : _map.camera.zoom);

  void _openSaved() => showFloatingSheet<void>(
    context,
    (_) => SavedSheet(
      catalog: _catalog!,
      places: _sets?.places ?? const [],
      pins: _pins,
      onPlaces: _places,
      onPins: _savePins,
      onShowPlace: (at) {
        setState(() => _tab = 0);
        _fly(at);
      },
      onShowStop: (stop) {
        setState(() => _tab = 0);
        _openStop(stop, fly: true);
      },
    ),
    scrollControlled: true,
  );

  Future<void> _menu(String choice) async {
    switch (choice) {
      case 'saved':
        _openSaved();
      case 'traffic':
        setState(() => _traffic = !_traffic);
      case 'map':
        showFloatingSheet<void>(
          context,
          (_) => ThemeSheet(current: _theme, onPick: _setTheme),
        );
      case 'lang':
        showFloatingSheet<void>(context, (_) => LanguageSheet(api: widget.api));
      case 'server':
        if (await editServer(context, widget.api) && mounted) widget.onOut();
      case 'out':
        await _signOut();
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.api.logout();
    } on Exception {
      // A session the server has already forgotten is still gone
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
    // No app bar or navigation bar: the chrome floats over a full-screen map,
    // so each piece is stacked with its own inset
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _tab,
            children: [
              MapTab(
                api: widget.api,
                map: _map,
                style: _style,
                traffic: _traffic,
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
                pins: _pins,
                places: _sets?.places ?? const [],
                shapes: _shapes,
                lines: _lines,
                arrowed: _onRoute ? _route : null,
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
                onLine: _openRoute,
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
                  onLine: _openRoute,
                  places: _sets?.places ?? const [],
                  onPlace: (end, at) => setState(() {
                    if (end == End.from) {
                      _from = at;
                    } else {
                      _to = at;
                    }
                  }),
                  onSave: _savePlace,
                  onForget: _forgetPlace,
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
            child: _onRoute && _route != null
                ? _RouteStrip(
                    route: catalog.routes[_route!],
                    onClose: _closeRoute,
                  )
                : _TopBar(
                    onSearch: _search,
                    onRoutes: () => _openRoutes(catalog),
                    onMenu: _menu,
                    server: widget.api.base,
                    traffic: _traffic,
                    lines: _allLines,
                    onLines: () {
                      setState(() => _allLines = !_allLines);
                      if (_allLines) unawaited(_geometry());
                    },
                  ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.paddingOf(context).bottom + floatingGap,
            child: Center(
              child: _Tabs(
                selected: _onRoute ? 3 : (_planning ? 2 : _tab),
                route: _route == null ? null : catalog.routes[_route!],
                onPick: _pickTab,
              ),
            ),
          ),
          _Status(live: live),
        ],
      ),
    );
  }

  void _pickTab(int i) {
    setState(() {
      _tab = i == 1 ? 1 : 0;
      _planning = i == 2;
      _onRoute = i == 3;
      if (!_planning) _picking = null;
    });
    _push();
  }

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
        _sets = Sets(
          sets: _sets!.sets,
          active: set.id,
          pins: _sets!.pins,
          places: _sets!.places,
        );
        _push();
      }),
      onSets: (sets) => setState(() => _sets = sets),
      onRoute: _openRoute,
    ),
    scrollControlled: true,
  );
}

/// Replaces the top bar while a route is open.
class _RouteStrip extends StatelessWidget {
  const _RouteStrip({required this.route, required this.onClose});

  final TransitRoute route;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Floating(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          RouteBadge(route: route),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              route.long,
              overflow: TextOverflow.ellipsis,
              style: material.Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    ),
  );
}

/// A search pill and the buttons that open everything else, floating over the
/// map and clear of the status bar.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onSearch,
    required this.onRoutes,
    required this.onMenu,
    required this.server,
    required this.lines,
    required this.onLines,
    required this.traffic,
  });

  final VoidCallback onSearch;
  final VoidCallback onRoutes;
  final void Function(String choice) onMenu;
  final String server;

  final bool lines;
  final VoidCallback onLines;

  /// Only to word its menu item, which is the toggle.
  final bool traffic;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Floating(
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
      RoundButton(
        tooltip: lines ? txt.hideEveryRoute : txt.everyRoute,
        onPressed: onLines,
        child: Icon(Icons.polyline_outlined, color: lines ? accent : null),
      ),
      const SizedBox(width: 8),
      Floating(
        shape: circle,
        child: PopupMenuButton<String>(
          onSelected: onMenu,
          itemBuilder: (_) => [
            PopupMenuItem(value: 'saved', child: Text(txt.saved)),
            PopupMenuItem(
              value: 'traffic',
              child: Text(traffic ? txt.hideTraffic : txt.traffic),
            ),
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

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.selected,
    required this.route,
    required this.onPick,
  });

  final int selected;

  /// Adds a fourth tab while it is open.
  final TransitRoute? route;
  final void Function(int index) onPick;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (Icons.map_outlined, txt.map),
      (Icons.schedule_outlined, txt.times),
      (Icons.directions_outlined, txt.plan),
      if (route != null) (Icons.timeline_outlined, txt.routeLine),
    ];
    return Floating(
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: tabBarHeight,
        // `IntrinsicWidth` over flexible children sizes every column to the
        // widest tab while keeping the bar only as wide as it needs to be
        child: IntrinsicWidth(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            // Stretch: a fill only as tall as its label reads as a highlight
            // rather than a button
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: on ? accent.withValues(alpha: 0.15) : null,
          borderRadius: BorderRadius.circular(tabBarHeight),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: on ? accent : Colors.white70),
              const SizedBox(width: 6),
              Text(
                label,
                // One weight either way: a heavier label is wider and would
                // shift the other tabs
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

/// A hairline along the top edge, red while the socket is away.
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
