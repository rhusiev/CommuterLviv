/// The map, the Mine tab, and the only place the shared state changes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'api.dart';
import 'follow.dart' show Stage, StageKind;
import 'follow_card.dart';
import 'followed.dart';
import 'haptics.dart';
import 'hold_sheet.dart';
import 'here.dart';
import 'lines.dart';
import 'lines_tab.dart';
import 'journey_panel.dart';
import 'live.dart';
import 'map_controls.dart' show nearZoom;
import 'map_tab.dart';
import 'map_theme.dart';
import 'mine_tab.dart';
import 'models.dart';
import 'password_dialog.dart';
import 'place_card.dart';
import 'quiet_banner.dart';
import 'server_dialog.dart';
import 'sheets.dart';
import 'stop_card.dart';
import 'stop_search.dart';
import 'theme.dart';
import 'tracking.dart';
import 'vehicle_card.dart';
import 'vehicle_layer.dart' show badgeRadius, pickableStops;
import 'walk_speed.dart';
import 'strings.dart';

/// How far a tap may land from a stop and still count.
const _hitRadius = 22.0;

/// The share of the screen the planner or an open line's panel may grow to,
/// the map keeping the rest.
const _panelShare = 0.6;

/// A dot in the planner's A/B ring: a place, but neither end of a journey
const _placeMark = '•';

/// The tabs, in the bar's order
const _mapTab = 0;
const _linesTab = 1;
const _journeyTab = 2;
const _mineTab = 3;

/// The most stops the server watches for one socket (`MAX_STOPS` in hub.py)
const _maxWatched = 64;

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
  bool _passwordChange = false;
  String? _error;

  final Set<int> _routes = {};

  /// The line open in the Lines tab. It outlives the tab, so leaving and
  /// coming back keeps it.
  int? _route;

  /// Which of the open line's directions its stops are listed for
  int _way = 0;

  /// Route ids of the lines opened lately, latest first
  late List<String> _recent = widget.api.recentLines;
  late bool _allLines = widget.api.showLines;
  Shapes? _shapes;
  List<int> _drawn = const [];

  /// The stops no route on the map calls at, drawn faint from close in.
  List<int> _faint = const [];
  List<int> _pins = const [];
  int? _stop;

  /// Map, Lines, Journey, Mine
  int _tab = _mapTab;

  /// Only while it is on does anything ask the server how the streets run.
  late bool _traffic = widget.api.showTraffic;
  late bool _followAway = widget.api.followAway;

  bool get _planning => _tab == _journeyTab;

  /// The open journey panel lies over the map buttons; folded or picking an
  /// end, it leaves them clear
  bool get _plannerOverButtons => _planning && !_folded && _picking == null;

  /// A panel lies over the map buttons: the open planner, or an open line once
  /// its stops are listed
  bool get _buttonsCovered =>
      _plannerOverButtons || (_lineOpen && _ways.isNotEmpty);

  /// One line, over the map, in place of the routes grid
  bool get _lineOpen => _tab == _linesTab && _route != null;

  /// Whether a page hides the map
  bool get _covered => _tab == _mineTab || (_tab == _linesTab && !_lineOpen);

  /// The planner option drawn on the map, only while planning
  Journey? _journey;
  LatLng? _from;

  /// The journey starts on board this vehicle, in place of `_from`; only
  /// while planning, as the vehicle goes on without the planner
  Aboard? _aboard;
  LatLng? _to;
  End? _picking;
  bool _folded = false;

  /// The journey being followed, from Follow on an option until it is ended,
  /// arrived or replaced. It outlives the planner and a restart, and while it
  /// lasts it is what the map draws
  Followed? _followed;
  Journey? get _following => _followed?.journey;

  /// The planner is to search as soon as both ends are set
  bool _ask = false;

  /// Picked by name, and marked on the map while its card is up
  LatLng? _place;

  /// What ends were called where they were chosen, for the planner to show
  final _named = <LatLng, String>{};

  /// Which end is waiting on a fix that has been asked for but not arrived.
  End? _wantHere;

  late final Here _here = Here(onFirstFix: (at) => _map.move(at, nearZoom));
  late final _tracking = Tracking(_map, _here);

  late MapTheme _theme = themeById(widget.api.mapTheme);
  Style? _style;

  @override
  void initState() {
    super.initState();
    _load();
    _loadStyle();
    if (_allLines) unawaited(_geometry());
    _here.addListener(_fixArrived);
  }

  @override
  void dispose() {
    _live?.dispose();
    _here.removeListener(_fixArrived);
    _tracking.stop();
    _here.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final catalog = await widget.api.catalog();
      final me = await widget.api.me();
      final sets = me.sets;
      final active = sets.sets.where((s) => s.id == sets.active).firstOrNull;
      final live = Live(widget.api, onRenewed: _renew)..open();
      if (!mounted) {
        live.dispose();
        return;
      }
      setState(() {
        _catalog = catalog;
        _sets = sets;
        _passwordChange = me.passwordChange;
        _live = live;
        _pins = catalog.stopsAt(sets.pins);
        _routes
          ..clear()
          ..addAll(catalog.routesAt(active?.routes ?? const []));
      });
      _push();
      _resume();
      await _carryOldPins(catalog, sets.pins);
    } on Exception catch (e) {
      if (e is ApiError && e.unauthorised) {
        widget.onOut();
      } else if (mounted) {
        setState(() => _error = widget.api.failure(e));
      }
    }
  }

  /// The service moved to a new feed. Every index held is carried over to the
  /// new catalog by its feed id; what was drawn from the old one is dropped.
  Future<void> _renew() async {
    final Catalog catalog;
    try {
      catalog = await widget.api.catalog();
    } on Exception {
      // The socket is held unsubscribed until then, so this must not give up
      if (mounted) Timer(const Duration(seconds: 5), _renew);
      return;
    }
    final old = _catalog;
    if (!mounted || old == null) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    final routes = catalog.routesAt([
      for (final i in _routes) old.routes[i].id,
    ]).toList();
    final route = _route == null
        ? null
        : catalog.routesAt([old.routes[_route!].id]).firstOrNull;
    setState(() {
      _catalog = catalog;
      _routes
        ..clear()
        ..addAll(routes);
      _pins = catalog.stopsAt([for (final i in _pins) old.stops[i].id]);
      _route = route;
      _stop = null;
      _journey = null;
      // Its stop and route positions are the old catalog's
      _followed = null;
      _shapes = null;
    });
    _tracking.stop();
    unawaited(widget.api.setFollowed(null));
    _push();
    if (_allLines || _route != null) unawaited(_geometry());
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(txt.renewed)));
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
    final (:stops, :faint) = catalog.splitStops(shown);
    setState(() {
      _drawn = stops;
      _faint = faint;
    });
    _watch();
  }

  /// What the socket sends: the open line alone, as it is all the map shows;
  /// while a journey is shown or followed, only its rides.
  Set<int> get _shown {
    if (_lineOpen) return {_route!};
    final rides = {
      for (final journey in [?_following, if (_planning) ?_journey])
        for (final leg in journey.legs)
          if (leg.route != null) leg.route!,
    };
    return rides.isNotEmpty ? rides : _routes;
  }

  /// The planner's option while planning, else the journey followed; nothing
  /// while a line is open.
  Journey? get _onMap => _lineOpen
      ? null
      : _planning
      ? _journey
      : _following;

  List<int> get _lines {
    if (_lineOpen) return [_route!];
    if (!_allLines) return const [];
    return [for (var i = 0; i < _catalog!.routes.length; i++) i];
  }

  /// Half a megabyte, so fetched lazily and only once.
  Future<void> _geometry() async {
    if (_shapes != null) return;
    try {
      final shapes = await widget.api.shapes();
      if (mounted) setState(() => _shapes = shapes);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = widget.api.failure(e));
    }
  }

  List<Place> _withoutPlace(String name) => [
    for (final p in _sets?.places ?? const <Place>[])
      if (p.name != name) p,
  ];

  /// Kept by name, so saving over a name elsewhere replaces that place - and
  /// is asked first, as the point it stood at is lost.
  Future<void> _savePlace(String name, LatLng at) async {
    final replaces = (_sets?.places ?? const <Place>[]).any(
      (p) => p.name.trim() == name.trim() && !p.isAt(at),
    );
    if (replaces && !await _mayReplace()) return;
    await _places([..._withoutPlace(name), Place(name: name, at: at)]);
  }

  /// True once the place of the name is to be replaced.
  Future<bool> _mayReplace() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog.adaptive(
          content: Text(txt.placeNameTaken),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(txt.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(txt.replace),
            ),
          ],
        ),
      ) ??
      false;

  /// What a long press on the map offers for [at].
  void _hold(LatLng at) => showFloatingSheet<void>(
    context,
    (_) => HoldSheet(
      at: at,
      onSave: (name) {
        Navigator.pop(context);
        unawaited(_savePlace(name, at));
      },
      onTo: () {
        Navigator.pop(context);
        _planTo(null, at);
      },
      onFrom: () {
        Navigator.pop(context);
        setState(() {
          _at(End.from, at);
          _ask = true;
        });
        _pickTab(2);
      },
      onNear: () {
        Navigator.pop(context);
        unawaited(_search(around: at));
      },
    ),
    scrollControlled: true,
  );

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
    } on Exception catch (e) {
      if (mounted) setState(() => _error = widget.api.failure(e));
    }
  }

  void _openRoute(int route) {
    final recent = opened(_recent, _catalog!.routes[route].id);
    setState(() {
      if (route != _route) _way = 0;
      _route = route;
      _recent = recent;
      _tab = _linesTab;
      _leavePlanner();
    });
    unawaited(widget.api.setRecentLines(recent));
    _push();
    _geometry().then((_) {
      if (!mounted) return;
      // The line's stops are known only from its shape
      _watch();
      final shape = _shapes?.routes.elementAtOrNull(route);
      final points = [
        for (final line in shape?.lines ?? const <RouteLine>[]) ...line.pts,
      ];
      if (points.isEmpty) return;
      _map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(40),
        ),
      );
    });
  }

  /// Back from the open line to the routes grid
  void _closeRoute() {
    setState(() => _route = null);
    _push();
  }

  /// The open line's ways, once the shapes are in
  List<Direction> get _ways => _route == null
      ? const []
      : directions(_shapes?.routes.elementAtOrNull(_route!));

  /// The server caps the watch list, so pins go first. A followed journey's
  /// stops are watched for when its vehicles get to them, and the open line's
  /// last, as the longest and the least needed.
  void _watch() {
    final line = _lineOpen
        ? _ways.elementAtOrNull(_way)?.stops ?? const <int>[]
        : const <int>[];
    _live?.setStops(
      {
        ..._pins,
        ?_stop,
        for (final leg in _following?.legs ?? const <Leg>[])
          if (leg.kind == 'ride') ...[leg.a, leg.b],
        ...line,
      }.take(_maxWatched).toList(),
    );
  }

  void _follow(Journey journey) {
    final followed = Followed(
      journey: journey,
      to: _to!,
      tag: widget.api.catalogTag ?? '',
    );
    unawaited(widget.api.setFollowed(jsonEncode(followed)));
    setState(() {
      _followed = followed;
      _tab = _mapTab;
      _leavePlanner();
    });
    _push();
    unawaited(_here.start());
    _tracking.start();
  }

  void _endFollow() {
    setState(() => _followed = null);
    unawaited(widget.api.setFollowed(null));
    _tracking.stop();
    _push();
  }

  /// Picks up the journey followed before the app was closed, if it still is
  void _resume() {
    final tag = widget.api.catalogTag;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final held = tag == null
        ? null
        : Followed.held(widget.api.followed, tag, now);
    if (held == null) return;
    setState(() => _followed = held);
    _push();
    unawaited(_here.start());
    _tracking.start();
  }

  /// Notes how far along the journey is; arrived, it is no longer kept
  void _moved(Stage stage) {
    final next = _followed?.at(stage);
    if (next != null) _followed = next;
    unawaited(widget.api.setFollowed(next == null ? null : jsonEncode(next)));
  }

  /// Plans the rest of the way: from on board the vehicle ridden, else from
  /// where you are. The journey is followed until another is.
  void _searchAgain(Stage stage) {
    final followed = _followed;
    if (followed == null) return;
    final veh = stage.kind == StageKind.ride ? stage.veh : null;
    setState(() {
      _to = followed.to;
      _from = null;
      _aboard = veh == null
          ? null
          : Aboard(veh, followed.journey.legs[stage.leg].route);
      _ask = true;
      _tab = _journeyTab;
    });
    _push();
    if (veh == null) unawaited(_hereFor(End.from));
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

  Future<void> _activateSet(RouteSet set) async {
    final catalog = _catalog;
    final sets = _sets;
    if (catalog == null || sets == null) return;
    try {
      await widget.api.activateSet(set.id);
    } on Exception catch (e) {
      _tell(widget.api.failure(e));
      return;
    }
    if (!mounted) return;
    setState(() {
      _routes
        ..clear()
        ..addAll(catalog.routesAt(set.routes));
      _sets = Sets(
        sets: sets.sets,
        active: set.id,
        pins: sets.pins,
        places: sets.places,
      );
    });
    _push();
  }

  /// Runs [change] against the server's sets and then shows them as the
  /// server now has them, since a rename or delete can also move the active one.
  Future<void> _changeSets(Future<Object?> Function() change) async {
    try {
      await change();
      final sets = await widget.api.sets();
      if (mounted) setState(() => _sets = sets);
    } on Exception catch (e) {
      _tell(widget.api.failure(e));
    }
  }

  void _tell(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _openStop(int stop, {bool fly = false}) {
    setState(() => _stop = stop);
    _watch();
    if (fly) {
      final s = _catalog!.stops[stop];
      _fly(LatLng(s.lat, s.lon));
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
        onRoute: _toggleRoute,
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

    var best = -1;
    var closest = _hitRadius * _hitRadius;
    for (final i in pickableStops(camera.zoom, _drawn, _faint)) {
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
        watching: _routes,
        onWatch: _toggleRoute,
        onRoute: (route) {
          Navigator.pop(context);
          _openRoute(route);
        },
        onAboard: (from) {
          Navigator.pop(context);
          setState(() {
            _aboard = from;
            _from = null;
            if (_wantHere == End.from) _wantHere = null;
          });
          _pickTab(2);
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
        _atHere(which, at);
      }
    });
  }

  void _fixArrived() {
    final which = _wantHere;
    final at = _here.fix?.point;
    if (which == null || at == null) return;
    setState(() {
      _atHere(which, at);
      _wantHere = null;
    });
  }

  /// Named, so the field reads as where I was rather than as coordinates.
  void _atHere(End which, LatLng at) {
    _named[at] = txt.useHere;
    _at(which, at);
  }

  void _at(End which, LatLng at) {
    if (which == End.from) {
      _from = at;
      _aboard = null;
    } else {
      _to = at;
    }
  }

  /// The search, listing the stops near [around] until something is typed.
  Future<void> _search({LatLng? around}) async {
    final catalog = _catalog;
    if (catalog == null) return;
    final hit = await showSearch<Hit?>(
      context: context,
      delegate: StopSearch(
        api: widget.api,
        catalog: catalog,
        places: _sets?.places ?? const [],
        onSave: _savePlace,
        here: _here,
        around: around,
      ),
    );
    if (hit == null || !mounted) return;
    setState(_uncover);
    switch (hit) {
      case StopHit(:final stop):
        _openStop(stop, fly: true);
      case PlaceHit(:final at, :final name, :final where):
        _openPlace(name, at, where: where);
    }
  }

  void _openPlace(String name, LatLng at, {String where = ''}) {
    setState(() {
      _uncover();
      _place = at;
    });
    _fly(at);
    showFloatingSheet<void>(
      context,
      (_) => PlaceCard(
        name: name,
        where: where,
        saved: _sets?.places.any((p) => p.isAt(at)) ?? false,
        onSave: () => unawaited(_savePlace(name, at)),
        onGo: () {
          Navigator.pop(context);
          _planTo(name, at);
        },
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _place = null);
    });
  }

  /// The planner, to [at] and from wherever it already starts - or from where
  /// you are, which is asked for only now. A point held on the map has no
  /// [name].
  void _planTo(String? name, LatLng at) {
    setState(() {
      _to = at;
      if (name != null) _named[at] = name;
      _ask = true;
    });
    _pickTab(2);
    if (_from == null && _aboard == null) unawaited(_hereFor(End.from));
  }

  /// Moves to [at], zooming in to [nearZoom] if further out, as the web does.
  void _fly(LatLng at) => _map.move(at, math.max(_map.camera.zoom, nearZoom));

  void _openLayers() => showFloatingSheet<void>(
    context,
    (_) => LayersSheet(
      lines: _allLines,
      onLines: (on) {
        setState(() => _allLines = on);
        unawaited(widget.api.setShowLines(on));
        if (on) unawaited(_geometry());
      },
      traffic: _traffic,
      onTraffic: (on) {
        setState(() => _traffic = on);
        unawaited(widget.api.setShowTraffic(on));
      },
      theme: _theme,
      onTheme: _setTheme,
    ),
    scrollControlled: true,
  );

  void _openAccount() => showFloatingSheet<void>(
    context,
    (sheet) => AccountSheet(
      server: widget.api.base,
      speed: widget.api.walkSpeed,
      hurry: widget.api.hurrySpeed,
      followAway: _followAway,
      onFollowAway: (on) {
        setState(() => _followAway = on);
        unawaited(widget.api.setFollowAway(on));
      },
      onLanguage: () {
        Navigator.pop(sheet);
        showFloatingSheet<void>(context, (_) => LanguageSheet(api: widget.api));
      },
      onSpeed: () {
        Navigator.pop(sheet);
        showFloatingSheet<void>(
          context,
          (_) => WalkSpeedSheet(api: widget.api),
        );
      },
      onServer: () async {
        Navigator.pop(sheet);
        if (await editServer(context, widget.api) && mounted) widget.onOut();
      },
      onPassword: _passwordChange ? () => _changePassword(sheet) : null,
      onOut: () {
        Navigator.pop(sheet);
        unawaited(_signOut());
      },
    ),
    scrollControlled: true,
  );

  Future<void> _changePassword(BuildContext sheet) async {
    Navigator.pop(sheet);
    if (await changePassword(context, widget.api) && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(txt.passwordChanged)));
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
      return _Failed(
        text: _error!,
        onRetry: () => setState(() {
          _error = null;
          _load();
          _loadStyle();
        }),
      );
    }
    if (catalog == null || live == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    // No app bar or navigation bar: the chrome floats over a full-screen map,
    // so each piece is stacked with its own inset
    return PopScope(
      // Back from another tab returns to the map, as Android's tabs do, rather
      // than leaving the app
      canPop: _tab == _mapTab,
      onPopInvokedWithResult: (didPop, _) {
        // On the map, what held back was a panel folding itself
        if (didPop || _tab == _mapTab) return;
        // Back from a line is to the routes grid, as its own back button goes
        _lineOpen ? _closeRoute() : _pickTab(_mapTab);
      },
      child: Scaffold(
        body: Stack(
          children: [
            IndexedStack(
              index: switch (_tab) {
                _mineTab => 2,
                _linesTab when !_lineOpen => 1,
                _ => 0,
              },
              children: [
                _mapPage(catalog, live),
                _linesPage(catalog),
                MineTab(
                  catalog: catalog,
                  live: live,
                  pins: _pins,
                  onPins: _savePins,
                  onStop: (stop) {
                    setState(_uncover);
                    _openStop(stop, fly: true);
                  },
                  watching: _routes,
                  onWatch: _toggleRoute,
                  onLine: _openRoute,
                  places: _sets?.places ?? const [],
                  onPlaces: _places,
                  onPlace: (place) => _openPlace(place.name, place.at),
                  sets: _sets,
                  onActivate: _activateSet,
                  onRename: (set, name) => _changeSets(
                    () => widget.api.updateSet(set.id, name, set.routes),
                  ),
                  onDelete: (set) =>
                      _changeSets(() => widget.api.deleteSet(set.id)),
                  username: widget.username,
                  onAccount: _openAccount,
                ),
              ],
            ),
            if (_planning) _planner(catalog),
            if (_lineOpen) _line(catalog, live),
            Positioned(
              left: floatingGap,
              right: floatingGap,
              top: MediaQuery.paddingOf(context).top + floatingGap,
              child: _TopBar(
                onSearch: _search,
                onLayers: _openLayers,
                layered: _allLines || _traffic,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom + floatingGap,
              child: Center(
                child: _Tabs(selected: _tab, onPick: _pickTab),
              ),
            ),
            Positioned(
              left: floatingGap,
              right: floatingGap,
              top: floatingTop(context),
              child: QuietBanner(live: live),
            ),
            _Status(live: live),
          ],
        ),
      ),
    );
  }

  Widget _mapPage(Catalog catalog, Live live) {
    return MapTab(
      api: widget.api,
      map: _map,
      style: _style,
      traffic: _traffic,
      catalog: catalog,
      live: live,
      stops: _drawn,
      faint: _faint,
      selected: _stop,
      theme: _theme,
      here: _here,
      onLocate: _following != null ? _tracking.start : null,
      card: _followCard(catalog, live),
      covered: _buttonsCovered,
      empty: _shown.isEmpty && _place == null,
      marks: [
        if (_planning && _from != null) (at: _from!, label: 'A'),
        if (_planning && _to != null) (at: _to!, label: 'B'),
        if (_place != null && !_planning) (at: _place!, label: _placeMark),
      ],
      journey: _onMap,
      pins: _pins,
      places: _sets?.places ?? const [],
      shapes: _shapes,
      lines: _lines,
      arrowed: _lineOpen ? _route : null,
      onTap: _tap,
      onHold: _hold,
    );
  }

  /// Offstage rather than gone, so the follower keeps what it has seen
  Widget? _followCard(Catalog catalog, Live live) {
    return _following == null
        ? null
        : Offstage(
            offstage: _planning,
            child: Padding(
              padding: const EdgeInsets.only(top: floatingGap),
              child: FollowCard(
                catalog: catalog,
                journey: _following!,
                live: live,
                here: _here,
                walkSpeed: widget.api.walkSpeed,
                hurrySpeed: widget.api.hurrySpeed,
                stage: _followed!.stage,
                away: _followAway,
                onMoved: _moved,
                onSearch: _searchAgain,
                onEnd: _endFollow,
              ),
            ),
          );
  }

  Widget _planner(Catalog catalog) {
    return Positioned(
      left: floatingGap,
      right: _plannerOverButtons
          ? floatingGap
          : floatingGap * 2 + kMinInteractiveDimension,
      bottom: floatingBottom(context),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * _panelShare,
        ),
        child: JourneyPanel(
          api: widget.api,
          catalog: catalog,
          from: _from,
          aboard: _aboard,
          to: _to,
          picking: _picking,
          onPick: (which) => setState(() => _picking = which),
          folded: _folded,
          onFold: (folded) => setState(() => _folded = folded),
          onSwap: () => setState(() {
            if (_aboard != null) return;
            final was = _from;
            _from = _to;
            _to = was;
          }),
          onHere: _hereFor,
          onStop: (stop) => _openStop(stop, fly: true),
          onLine: _openRoute,
          places: _sets?.places ?? const [],
          named: _named,
          onPlace: (end, at) => setState(() => _at(end, at)),
          onSave: _savePlace,
          onShow: (journey) {
            setState(() => _journey = journey);
            _push();
          },
          onFollow: _follow,
          ask: _ask,
          onAsked: () => setState(() => _ask = false),
        ),
      ),
    );
  }

  void _pickTab(int i) {
    setState(() {
      _tab = i;
      if (!_planning) _leavePlanner();
    });
    _push();
  }

  /// Drops what the planner held for the map
  void _leavePlanner() {
    _aboard = null;
    _picking = null;
    _folded = false;
    _journey = null;
  }

  /// Back to the map from a page that hides it; the planner and an open line
  /// already show it
  void _uncover() {
    if (_covered) _tab = _mapTab;
  }

  Widget _linesPage(Catalog catalog) => LinesTab(
    api: widget.api,
    catalog: catalog,
    sets: _sets,
    picked: _routes,
    onToggle: _toggleRoute,
    onClear: () {
      setState(_routes.clear);
      _push();
    },
    onActivated: (set, routes) {
      setState(() {
        _routes
          ..clear()
          ..addAll(routes);
        _sets = Sets(
          sets: _sets!.sets,
          active: set.id,
          pins: _sets!.pins,
          places: _sets!.places,
        );
      });
      _push();
    },
    onSets: (sets) => setState(() => _sets = sets),
    onOpen: _openRoute,
    recent: _recent,
    here: _here,
  );

  Widget _line(Catalog catalog, Live live) => Positioned(
    left: floatingGap,
    right: floatingGap,
    top: floatingTop(context),
    bottom: floatingBottom(context),
    child: Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * _panelShare,
        ),
        child: LinePanel(
          catalog: catalog,
          live: live,
          route: _route!,
          ways: _ways,
          way: _way,
          onWay: (way) {
            setState(() => _way = way);
            _watch();
          },
          watching: _routes.contains(_route),
          onWatch: () => _toggleRoute(_route!),
          onStop: (stop) => _openStop(stop, fly: true),
          onBack: _closeRoute,
        ),
      ),
    ),
  );
}

/// A search pill and the layers button, floating over the map and clear of
/// the status bar.
///
/// Only what changes the map sits on it. Which routes are tracked is the Lines
/// tab's, and what is kept and how the app is set up the Mine tab's, so nothing
/// that signs you out sits loose on the map.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onSearch,
    required this.onLayers,
    required this.layered,
  });

  final VoidCallback onSearch;
  final VoidCallback onLayers;

  /// Whether anything inside the layers sheet is on, which is the only sign the
  /// map gives that the sheet is holding something.
  final bool layered;

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
        tooltip: txt.layers,
        onPressed: onLayers,
        child: Icon(Icons.layers_outlined, color: layered ? accent : null),
      ),
    ],
  );
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.selected, required this.onPick});

  final int selected;
  final void Function(int index) onPick;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (Icons.map_outlined, txt.map),
      (Icons.timeline_outlined, txt.lines),
      (Icons.directions_outlined, txt.plan),
      (Icons.person_outline, txt.mine),
    ];
    return Floating(
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: tabBarHeight,
        // Four labelled tabs are wider than a phone, so only the picked one
        // keeps its label
        child: Row(
          mainAxisSize: MainAxisSize.min,
          // Stretch: a fill only as tall as its label reads as a highlight
          // rather than a button
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, (icon, label)) in tabs.indexed)
              _Tab(
                icon: icon,
                label: label,
                bare: i != selected,
                on: i == selected,
                onTap: () => onPick(i),
              ),
          ],
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
    this.bare = false,
  });

  final IconData icon;
  final String label;

  /// Shows the label only as a tooltip.
  final bool bare;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tab = InkWell(
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
                if (!bare) ...[
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
              ],
            ),
          ),
        ),
      ),
    );
    return bare ? Tooltip(message: label, child: tab) : tab;
  }
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

class _Failed extends StatelessWidget {
  const _Failed({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CommuterLviv')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: Text(txt.tryAgain)),
          ],
        ),
      ),
    );
  }
}
