/// What to do now on a journey being followed, from the bottom of the map; a
/// tap on it lists every step.
library;

import 'dart:async';

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;

import 'eta.dart';
import 'follow.dart';
import 'here.dart' show Here, Locating;
import 'legs.dart';
import 'live.dart';
import 'models.dart';
import 'route_badge.dart';
import 'strings.dart';
import 'theme.dart';

const _mPerKm = 1000;

/// Short distances are said to this many metres
const _stepM = 10;

/// The steps list scrolls past this height
const _stepsMaxHeight = 256.0;

/// Room for a step's `HH:MM - HH:MM`
const _clockWidth = 96.0;

/// Follows [journey] from [here]'s fixes for as long as it is mounted. The
/// fixes go nowhere but the follower.
class FollowCard extends StatefulWidget {
  const FollowCard({
    super.key,
    required this.catalog,
    required this.journey,
    required this.live,
    required this.here,
    required this.away,
    required this.onEnd,
  });

  final Catalog catalog;
  final Journey journey;
  final Live live;
  final Here here;

  /// Whether to go on with the app off the screen, on a notification
  final bool away;
  final VoidCallback onEnd;

  @override
  State<FollowCard> createState() => _FollowCardState();
}

class _FollowCardState extends State<FollowCard> {
  late Follower _follower = Follower(widget.journey, widget.catalog);
  Progress? _progress;

  /// Every step of the journey is listed
  bool _steps = false;

  /// What the notification last said, so a fix that changes nothing in it
  /// is not sent on
  String? _noticed;

  /// The moments already sounded for: getting off soon, past the stop,
  /// arrived - each once per leg
  final _alerted = <String>{};

  @override
  void initState() {
    super.initState();
    widget.here.addListener(_fixArrived);
    widget.live.addListener(_redraw);
    _fixArrived();
    if (widget.away) _goAway(true);
  }

  @override
  void didUpdateWidget(FollowCard old) {
    super.didUpdateWidget(old);
    if (old.journey != widget.journey) {
      _follower = Follower(widget.journey, widget.catalog);
      _progress = null;
      _noticed = null;
      _alerted.clear();
    }
    if (old.here != widget.here) {
      old.here.removeListener(_fixArrived);
      widget.here.addListener(_fixArrived);
    }
    if (old.live != widget.live) {
      old.live.removeListener(_redraw);
      widget.live.addListener(_redraw);
    }
    if (old.away != widget.away) _goAway(widget.away);
  }

  @override
  void dispose() {
    widget.here.removeListener(_fixArrived);
    widget.live.removeListener(_redraw);
    if (widget.away) _goAway(false);
    super.dispose();
  }

  void _goAway(bool on) {
    _noticed = null;
    unawaited(
      widget.here
          .away(on, channel: txt.followChannel, alerts: txt.alertChannel)
          .then((_) => on && mounted ? _notice() : null),
    );
  }

  _Said _said(Progress p) =>
      _say(widget.catalog, widget.journey, widget.live, p);

  TransitRoute? _route(Progress p) {
    if (p.stage.kind == StageKind.walk || p.stage.kind == StageKind.arrived) {
      return null;
    }
    return _routeOf(widget.catalog, widget.journey.legs[p.stage.leg].route);
  }

  /// Repeats the card on the notification, sounding once for each moment
  /// worth taking the phone out for.
  void _notice() {
    final progress = _progress;
    if (!widget.away || progress == null) return;
    final said = _said(progress);
    final leg = progress.stage.leg;
    final moment = switch (progress) {
      Progress(stage: Stage(kind: StageKind.arrived)) => 'arrived',
      Progress(passed: true) => 'passed $leg',
      Progress(soon: true) => 'soon $leg',
      _ => null,
    };
    final alert = moment != null && _alerted.add(moment);
    final text = '${said.head}\n${said.line}';
    if (!alert && text == _noticed) return;
    _noticed = text;
    unawaited(widget.here.notice(said.head, said.line, alert: alert));
  }

  /// The arrivals moved on, so the times said are redrawn.
  void _redraw() {
    setState(() {});
    _notice();
  }

  /// `Here` also notifies on a change of state, and the follower turns away a
  /// fix it has already had by its time.
  void _fixArrived() {
    final fix = widget.here.fix;
    if (fix == null) {
      setState(() {});
      return;
    }
    // Where the map draws each vehicle at this moment, which is all the
    // follower has to tell the one ridden from the one beside it
    final live = widget.live;
    final now = live.nowMs;
    final seen = <Seen>[];
    for (final MapEntry(key: id, value: v) in live.vehicles.entries) {
      final p = sample(v, now);
      seen.add(Seen(id: id, route: v.route, lat: p.lat, lon: p.lon));
    }
    setState(
      () => _progress = _follower.update(
        Fix(
          lat: fix.point.latitude,
          lon: fix.point.longitude,
          accuracy: fix.accuracy,
          t: fix.t,
        ),
        seen,
      ),
    );
    _notice();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final done = progress?.stage.kind == StageKind.arrived;
    final faint = material.Theme.of(context).textTheme.bodySmall;
    return Floating(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(panelRadius),
        side: const BorderSide(color: hair),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: _steps ? txt.hideSteps : txt.showSteps,
                    child: InkWell(
                      onTap: () => setState(() => _steps = !_steps),
                      child: Row(
                        children: [
                          Expanded(
                            child: progress != null
                                ? _Step(
                                    said: _said(progress),
                                    route: _route(progress),
                                  )
                                : widget.here.state == Locating.denied
                                ? Text(
                                    txt.noLocation,
                                    style: TextStyle(
                                      color: material.Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  )
                                : Text(txt.locating, style: faint),
                          ),
                          Icon(
                            _steps ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                done
                    ? FilledButton(
                        onPressed: widget.onEnd,
                        child: Text(txt.endFollow),
                      )
                    : TextButton(
                        onPressed: widget.onEnd,
                        child: Text(txt.endFollow),
                      ),
              ],
            ),
            if (_steps)
              _Steps(
                catalog: widget.catalog,
                journey: widget.journey,
                stage: progress?.stage,
              ),
          ],
        ),
      ),
    );
  }
}

/// What the card says at one moment, and what the notification repeats.
class _Said {
  const _Said(this.head, this.sub, this.warning, {this.passed = false});

  final String head;
  final String? sub;
  final String? warning;

  /// The warning is about the stop to get off at, not about the way
  final bool passed;

  String get line => [?sub, ?warning].join(' · ');
}

_Said _say(Catalog catalog, Journey journey, Live live, Progress progress) {
  final stage = progress.stage;
  if (stage.kind == StageKind.arrived) return _Said(txt.arrived, null, null);
  final leg = journey.legs[stage.leg];
  String name(int stop) => _stopName(catalog, stop);
  List<Arrival> due(int stop) => [
    for (final a in live.arrivals[stop] ?? const <Arrival>[])
      if (a.route == leg.route) a,
  ];
  final String head;
  Arrival? when;
  switch (stage.kind) {
    case StageKind.walk:
      head = leg.b < 0 ? txt.walkHome : txt.walkTo(name(leg.b));
    case StageKind.wait:
      // The planned vehicle, or the route's next one when it is not coming
      final at = due(leg.a);
      head = txt.waitAt(name(leg.a));
      when = at.where((a) => a.veh == leg.veh).firstOrNull ?? at.firstOrNull;
    default:
      // Only the vehicle ridden says when it gets there; another of its
      // route could be the one ahead
      head = progress.soon ? txt.offSoon(name(leg.b)) : txt.offAt(name(leg.b));
      when = stage.veh == null
          ? null
          : due(leg.b).where((a) => a.veh == stage.veh).firstOrNull;
  }
  final sub = stage.kind == StageKind.wait
      ? (when == null ? null : txt.dueIn(countdown(when.t)))
      : [
          txt.toGo(_distance(progress.left)),
          if (when != null) countdown(when.t),
        ].join(' · ');
  return progress.passed
      ? _Said(head, sub, txt.passedStop, passed: true)
      : _Said(head, sub, progress.astray ? txt.offTheWay : null);
}

class _Step extends StatelessWidget {
  const _Step({required this.said, required this.route});

  final _Said said;
  final TransitRoute? route;

  @override
  Widget build(BuildContext context) {
    final theme = material.Theme.of(context);
    final warning = said.warning;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (route != null) ...[
              RouteBadge(route: route!, fontSize: 10),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                said.head,
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (said.sub != null) Text(said.sub!, style: theme.textTheme.bodySmall),
        if (warning != null)
          Text(
            warning,
            style: theme.textTheme.bodySmall?.copyWith(
              color: said.passed ? theme.colorScheme.error : Colors.amber,
            ),
          ),
      ],
    );
  }
}

/// Every walk, wait and ride of the journey with when it starts and ends, the
/// one under way marked
class _Steps extends StatelessWidget {
  const _Steps({
    required this.catalog,
    required this.journey,
    required this.stage,
  });

  final Catalog catalog;
  final Journey journey;

  /// Where the journey is, or null while that is not known
  final Stage? stage;

  @override
  Widget build(BuildContext context) {
    final list = rows(journey);
    final now = stage == null ? -1 : current(list, stage!);
    final theme = material.Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.only(top: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: hair)),
      ),
      constraints: const BoxConstraints(maxHeight: _stepsMaxHeight),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          for (final (i, row) in list.indexed)
            Container(
              key: ValueKey(('step', i)),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              decoration: i == now
                  ? BoxDecoration(
                      color: raised,
                      borderRadius: BorderRadius.circular(6),
                    )
                  : null,
              child: DefaultTextStyle.merge(
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: i < now ? theme.disabledColor : null,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: _clockWidth,
                      child: Text(
                        '${clockTime(row.dep)} - ${clockTime(row.arr)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    ..._what(row),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _what(PlanRow row) {
    String name(int stop) => _stopName(catalog, stop);
    final route = _routeOf(catalog, row.route);
    final (Widget lead, String text) = switch (row.kind) {
      PlanRowKind.ride => (
        route == null
            ? const SizedBox.shrink()
            : RouteBadge(route: route, fontSize: 10),
        '${name(row.a)} → ${name(row.b)}',
      ),
      PlanRowKind.wait => (
        const Icon(Icons.schedule, size: 16),
        txt.waitAt(name(row.a)),
      ),
      PlanRowKind.walk => (
        const Icon(Icons.directions_walk, size: 16),
        row.b < 0
            ? txt.walkHome
            : row.change
            ? txt.changeAt(name(row.b))
            : txt.walkTo(name(row.b)),
      ),
    };
    return [
      lead,
      const SizedBox(width: 6),
      Expanded(child: Text(text, overflow: TextOverflow.ellipsis)),
    ];
  }
}

/// A stop's name; the server sends -1 for a stop the catalog lacks
String _stopName(Catalog catalog, int stop) =>
    stop >= 0 && stop < catalog.stops.length ? catalog.stops[stop].name : '';

TransitRoute? _routeOf(Catalog catalog, int? route) =>
    route != null && route >= 0 && route < catalog.routes.length
    ? catalog.routes[route]
    : null;

String _distance(double m) => m < _mPerKm
    ? txt.metres((m / _stepM).round() * _stepM)
    : txt.km(m / _mPerKm);
