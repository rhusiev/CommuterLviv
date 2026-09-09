/// The app proper: a map of the city, and the times at the stops you pinned.
///
/// One screen owns all the state the two tabs share - the catalog, the socket,
/// which routes are shown, which stops are pinned - because both tabs are
/// views of the same subscription. Everything else here is a sheet.
library;

import 'dart:async';

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import '../main.dart' show tick;
import 'api.dart';
import 'eta.dart';
import 'live.dart';
import 'map_controls.dart';
import 'map_tiles.dart';
import 'map_theme.dart';
import 'models.dart';
import 'server_dialog.dart';
import 'vehicle_layer.dart';

const _lviv = LatLng(49.8397, 24.0297);

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
        setState(() => _error = 'could not reach ${widget.api.base}');
      }
    }
  }

  /// The sheets are separate widgets but they edit this screen's state, so they
  /// need a way to say so that is not `setState` from outside a `State`
  void update(VoidCallback change) {
    if (mounted) setState(change);
  }

  Iterable<int> _indexes(Catalog catalog, List<String> ids) =>
      ids.map((id) => catalog.index[id]).whereType<int>();

  /// Pinned stops arrive as feed ids and are used as catalog positions. A stop
  /// the city has since dropped simply does not resolve.
  List<int> _resolve(Catalog catalog, List<String> ids) =>
      [for (final id in ids) ?catalog.stopIndex[id]];

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
      if (mounted) setState(() => _error = 'the basemap would not load');
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
      builder: (_) => _StopCard(
        home: this,
        stop: stop,
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
      delegate: _StopSearch(catalog),
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
          builder: (_) => _ThemeSheet(home: this),
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
                child: const Text('Try again'),
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
            tooltip: 'Find a stop',
          ),
          IconButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              builder: (_) => _RouteSheet(home: this),
            ),
            icon: const Icon(Icons.route_outlined),
            tooltip: 'Routes',
          ),
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'map', child: Text('Map style')),
              PopupMenuItem(
                value: 'server',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Server'),
                  subtitle: Text(widget.api.base),
                ),
              ),
              const PopupMenuItem(value: 'out', child: Text('Sign out')),
            ],
          ),
        ],
        bottom: _Status(live: live),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _MapTab(home: this),
          _TimesTab(home: this),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
          NavigationDestination(
            icon: Icon(Icons.schedule_outlined),
            label: 'Times',
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

class _MapTab extends StatelessWidget {
  const _MapTab({required this.home});

  final _HomeScreenState home;

  @override
  Widget build(BuildContext context) {
    final style = home._style;
    return Stack(
      children: [
        FlutterMap(
          mapController: home._map,
          options: MapOptions(
            initialCenter: _lviv,
            initialZoom: 13,
            minZoom: minZoom,
            maxZoom: maxZoom,
            onTap: (_, point) => home._tap(point),
            interactionOptions: mapInteraction,
          ),
          children: [
            if (style != null)
              VectorTileLayer(
                tileProviders: style.providers,
                theme: style.theme,
                sprites: style.sprites,
                // The renderer's own frame budget: below this it drops detail
                // rather than the frame, which is the right trade on a phone
                maximumZoom: 18,
                // `analyze` resolves the package's conditional export to its
                // web stub, where its `Directory` is a `String`; the compiler
                // picks the `dart:io` one this actually gets
                // ignore: argument_type_not_assignable
                cacheFolder: tileCache,
                fileCacheTtl: tileTtl,
                fileCacheMaximumSizeInBytes: tileDiskBytes,
                memoryTileCacheMaxSize: tileMemoryBytes,
                memoryTileDataCacheMaxSize: tileMemoryCount,
              ),
            VehicleLayer(
              catalog: home._catalog!,
              live: home._live!,
              stops: home._drawn,
              selected: home._stop,
              theme: home._theme,
            ),
            const SimpleAttributionWidget(
              source: Text('OpenStreetMap · VersaTiles'),
              alignment: Alignment.bottomLeft,
            ),
          ],
        ),
        Positioned(right: 12, bottom: 24, child: MapControls(map: home._map)),
        if (style == null) const LinearProgressIndicator(minHeight: 2),
        if (home._routes.isEmpty)
          const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Pick a route to see it moving'),
              ),
            ),
          ),
      ],
    );
  }
}

class _TimesTab extends StatelessWidget {
  const _TimesTab({required this.home});

  final _HomeScreenState home;

  @override
  Widget build(BuildContext context) {
    if (home._pins.isEmpty) {
      return const Center(child: Text('Pin a stop and its times show up here'));
    }
    return AnimatedBuilder(
      animation: home._live!,
      builder: (context, _) => ListView(
        children: [
          for (final stop in home._pins)
            _StopTile(
              home: home,
              stop: stop,
              arrivals: home._live!.arrivals[stop] ?? const [],
            ),
        ],
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.home,
    required this.stop,
    required this.arrivals,
  });

  final _HomeScreenState home;
  final int stop;
  final List<Arrival> arrivals;

  @override
  Widget build(BuildContext context) {
    final s = home._catalog!.stops[stop];
    return ListTile(
      title: Text(s.name),
      subtitle: arrivals.isEmpty
          ? const Text('nothing due')
          : Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final a in arrivals.take(6)) _Due(home: home, arrival: a),
              ],
            ),
      trailing: IconButton(
        onPressed: () => home._pin(stop),
        icon: const Icon(Icons.push_pin),
        tooltip: 'Unpin',
      ),
      onTap: () {
        home.update(() => home._tab = 0);
        home._openStop(stop, fly: true);
      },
    );
  }
}

/// A route badge and how long until it calls. Half a minute away reads "now",
/// because "0 min" invites the reader to think it is late rather than here.
class _Due extends StatelessWidget {
  const _Due({required this.home, required this.arrival});

  final _HomeScreenState home;
  final Arrival arrival;

  @override
  Widget build(BuildContext context) {
    final route = home._catalog!.routes[arrival.route];
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: CircleAvatar(
        backgroundColor: routeColour(route.short, route.type),
        child: Text(
          route.short,
          style: const TextStyle(fontSize: 9, color: Color(0xff0b0f14)),
        ),
      ),
      label: Text(countdown(arrival.t)),
    );
  }
}

class _StopCard extends StatelessWidget {
  const _StopCard({
    required this.home,
    required this.stop,
    required this.onRoute,
  });

  final _HomeScreenState home;
  final int stop;
  final void Function(int route) onRoute;

  @override
  Widget build(BuildContext context) {
    final catalog = home._catalog!;
    final s = catalog.stops[stop];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.name,
                    style: material.Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => home._pin(stop),
                  icon: Icon(
                    home._pins.contains(stop)
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                  ),
                  tooltip: home._pins.contains(stop) ? 'Unpin' : 'Pin',
                ),
              ],
            ),
            if (s.code.isNotEmpty) Text(s.code),
            const SizedBox(height: 8),
            AnimatedBuilder(
              animation: home._live!,
              builder: (context, _) {
                final due = home._live!.arrivals[stop] ?? const <Arrival>[];
                if (due.isEmpty) {
                  return const Text(
                    'nothing due on the routes you are watching',
                  );
                }
                return Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final a in due.take(8)) _Due(home: home, arrival: a),
                  ],
                );
              },
            ),
            const Divider(height: 24),
            Text(
              'Calls here',
              style: material.Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final r in s.routes)
                  ActionChip(
                    label: Text(catalog.routes[r].short),
                    avatar: home._routes.contains(r)
                        ? const Icon(Icons.check, size: 16)
                        : null,
                    onPressed: () => onRoute(r),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSheet extends StatelessWidget {
  const _ThemeSheet({required this.home});

  final _HomeScreenState home;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final t in mapThemes)
          ListTile(
            onTap: () {
              Navigator.pop(context);
              home._setTheme(t);
            },
            title: Text(t.name),
            subtitle: Text(t.dark ? 'dark' : 'light'),
            trailing: t.id == home._theme.id ? const Icon(Icons.check) : null,
          ),
      ],
    ),
  );
}

/// Routes, and the saved sets of routes. Sets live on the server so the phone
/// and the browser show the same thing; which routes are ticked right now is
/// only ticked here until it is saved as one.
class _RouteSheet extends StatefulWidget {
  const _RouteSheet({required this.home});

  final _HomeScreenState home;

  @override
  State<_RouteSheet> createState() => _RouteSheetState();
}

class _RouteSheetState extends State<_RouteSheet> {
  String _filter = '';

  _HomeScreenState get home => widget.home;

  Future<void> _save() async {
    final catalog = home._catalog!;
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        final field = TextEditingController();
        return AlertDialog.adaptive(
          title: const Text('Name this set'),
          content: TextField(controller: field, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, field.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    final ids = [for (final i in home._routes) catalog.routes[i].id];
    final made = await home.widget.api.createSet(name, ids);
    await home.widget.api.activateSet(made.id);
    final sets = await home.widget.api.sets();
    if (mounted) {
      home.update(() => home._sets = sets);
      setState(() {});
    }
  }

  Future<void> _activate(RouteSet set) async {
    final catalog = home._catalog!;
    await home.widget.api.activateSet(set.id);
    home._routes
      ..clear()
      ..addAll(home._indexes(catalog, set.routes));
    home._push();
    if (mounted) {
      home.update(
        () => home._sets = Sets(
          sets: home._sets!.sets,
          active: set.id,
          pins: home._sets!.pins,
        ),
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = home._catalog!;
    final needle = _filter.toLowerCase();
    final shown = [
      for (var i = 0; i < catalog.routes.length; i++)
        if (needle.isEmpty ||
            catalog.routes[i].short.toLowerCase().contains(needle) ||
            catalog.routes[i].long.toLowerCase().contains(needle))
          i,
    ];
    final sets = home._sets?.sets ?? const <RouteSet>[];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (sets.isNotEmpty) ...[
            Text(
              'Sets',
              style: material.Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final s in sets)
                  ChoiceChip(
                    label: Text(s.name),
                    selected: s.id == home._sets?.active,
                    onSelected: (_) => _activate(s),
                  ),
              ],
            ),
            const Divider(height: 24),
          ],
          TextField(
            onChanged: (v) => setState(() => _filter = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Filter routes',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final i in shown)
                FilterChip(
                  label: Text(catalog.routes[i].short),
                  tooltip: catalog.routes[i].long,
                  selected: home._routes.contains(i),
                  onSelected: (_) {
                    home._toggleRoute(i);
                    setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: home._routes.isEmpty
                    ? null
                    : () {
                        home._routes.clear();
                        home._push();
                        setState(() {});
                      },
                child: const Text('Clear'),
              ),
              const Spacer(),
              FilledButton.tonal(
                onPressed: home._routes.isEmpty ? null : _save,
                child: const Text('Save as a set'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Stops by name. The catalog is a thousand stops, which is small enough to
/// scan on every keystroke and not worth an index.
class _StopSearch extends SearchDelegate<int?> {
  _StopSearch(this.catalog) : super(searchFieldLabel: 'Find a stop');

  final Catalog catalog;

  @override
  List<Widget> buildActions(BuildContext context) => [
    if (query.isNotEmpty)
      IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear)),
  ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const BackButtonIcon(),
  );

  @override
  Widget buildResults(BuildContext context) => buildSuggestions(context);

  @override
  Widget buildSuggestions(BuildContext context) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const SizedBox.shrink();
    final hits = [
      for (var i = 0; i < catalog.stops.length; i++)
        if (catalog.stops[i].name.toLowerCase().contains(needle)) i,
    ];
    return ListView.builder(
      itemCount: hits.length,
      itemBuilder: (context, k) {
        final s = catalog.stops[hits[k]];
        return ListTile(
          title: Text(s.name),
          subtitle: Text(
            [for (final r in s.routes) catalog.routes[r].short].join(' · '),
          ),
          onTap: () => close(context, hits[k]),
        );
      },
    );
  }
}
