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
import 'live.dart';
import 'map_tab.dart';
import 'map_theme.dart';
import 'models.dart';
import 'server_dialog.dart';
import 'sheets.dart';
import 'stop_card.dart';
import 'stop_search.dart';
import 'times_tab.dart';
import 'vehicle_layer.dart' show stopsZoom;
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

  late MapTheme _theme = themeById(widget.api.mapTheme);
  Style? _style;

  @override
  void initState() {
    super.initState();
    _load();
    _loadStyle();
  }

  @override
  void dispose() {
    _live?.dispose();
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
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => StopCard(
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
    final camera = _map.camera;
    if (camera.zoom < stopsZoom) return;
    final at = camera.latLngToScreenOffset(point);
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
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (_) => ThemeSheet(current: _theme, onPick: _setTheme),
        );
      case 'lang':
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (_) => LanguageSheet(api: widget.api),
        );
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('CommuterLviv'),
        actions: [
          IconButton(
            onPressed: _search,
            icon: const Icon(Icons.search),
            tooltip: txt.findStop,
          ),
          IconButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              builder: (_) => RouteSheet(
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
                  );
                  _push();
                }),
                onSets: (sets) => setState(() => _sets = sets),
              ),
            ),
            icon: const Icon(Icons.route_outlined),
            tooltip: txt.routes,
          ),
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => [
              PopupMenuItem(value: 'map', child: Text(txt.mapStyle)),
              PopupMenuItem(value: 'lang', child: Text(txt.language)),
              PopupMenuItem(
                value: 'server',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(txt.server),
                  subtitle: Text(widget.api.base),
                ),
              ),
              PopupMenuItem(value: 'out', child: Text(txt.signOut)),
            ],
          ),
        ],
        bottom: _Status(live: live),
      ),
      body: IndexedStack(
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
            empty: _routes.isEmpty,
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.map_outlined),
            label: txt.map,
          ),
          NavigationDestination(
            icon: const Icon(Icons.schedule_outlined),
            label: txt.times,
          ),
        ],
      ),
    );
  }
}

/// A one-pixel line under the app bar, red while the socket is away. Anything
/// larger would be a banner about a state that is usually over in a second.
class _Status extends StatelessWidget implements PreferredSizeWidget {
  const _Status({required this.live});

  final Live live;

  @override
  Size get preferredSize => const Size.fromHeight(2);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: live,
    builder: (context, _) => live.connection == Connection.live
        ? const SizedBox(height: 2)
        : LinearProgressIndicator(
            minHeight: 2,
            color: material.Theme.of(context).colorScheme.error,
          ),
  );
}
