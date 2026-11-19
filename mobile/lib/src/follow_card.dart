/// What to do now on a journey being followed, from the bottom of the map; a
/// tap on it lists every step.
library;

import 'dart:async';
import 'dart:math' show max;

import 'package:clock/clock.dart';
import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;

import 'eta.dart';
import 'follow.dart';
import 'here.dart' show Here, Locating;
import 'hurry_pill.dart';
import 'legs.dart';
import 'live.dart';
import 'models.dart';
import 'route_badge.dart';
import 'strings.dart';
import 'theme.dart';

const _mPerKm = 1000;
const _kmhPerMps = 3.6;
const _msPerS = 1000;

/// Short distances are said to this many metres
const _stepM = 10;

/// How often the next connection is judged again when no fix or arrivals
/// prompt it, so a word [Watch] holds back is said when its hold ends and the
/// time left counts down. Chosen, not derived
const _judgeEvery = Duration(seconds: 1);

/// The steps list scrolls past this height
const _stepsMaxHeight = 256.0;

/// A long stop name wraps rather than losing its end, as on the web
const _headLines = 2;

/// Room for a step's `HH:MM - HH:MM`
const _clockWidth = 96.0;

/// How long the card says the route was updated
const _updatedSaidS = 15;

/// Follows [journey] from [here]'s fixes for as long as it is mounted. The
/// fixes go nowhere but the follower.
class FollowCard extends StatefulWidget {
  const FollowCard({
    super.key,
    required this.catalog,
    required this.journey,
    required this.live,
    required this.here,
    required this.walkSpeed,
    required this.hurrySpeed,
    required this.away,
    required this.onMoved,
    this.onProgress,
    required this.onSearch,
    required this.onRebuild,
    required this.onEnd,
    this.onCaught,
    this.updatedAt,
    this.stage,
  });

  final Catalog catalog;
  final Journey journey;
  final Live live;
  final Here here;

  /// In km/h; [hurrySpeed] is null while hurrying is off
  final double walkSpeed;
  final double? hurrySpeed;

  /// Where on the journey to start from, as held from an earlier run
  final Stage? stage;

  /// Whether to go on with the app off the screen, on a notification
  final bool away;

  /// The follower moved on to another stage
  final void Function(Stage) onMoved;

  /// Each fix's progress, for drawing the walk under way from it.
  final ValueChanged<Progress>? onProgress;

  /// Another way is asked for, from where the follower is
  final void Function(Stage) onSearch;

  /// The way to the next stop is searched again from where the device is,
  /// having strayed from the one walked
  final void Function(Stage) onRebuild;
  final VoidCallback onEnd;

  /// Whether the next ride is still caught, as the card last judged it
  final ValueChanged<Catch>? onCaught;

  /// When the route was last searched again and changed, Unix seconds
  final int? updatedAt;

  @override
  State<FollowCard> createState() => _FollowCardState();
}

class _FollowCardState extends State<FollowCard> {
  late Follower _follower = _start();
  Progress? _progress;
  var _watch = Watch();
  Catch _caught = const Catch(CatchKind.ok);

  /// Every step of the journey is listed
  bool _steps = false;

  /// What the notification last said, so a fix that changes nothing in it
  /// is not sent on
  String? _noticed;

  /// The moments already sounded for: getting off soon, past the stop, the
  /// next ride caught only by hurrying or missed, arrived - each once per leg
  final _alerted = <String>{};

  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    widget.here.addListener(_fixArrived);
    widget.live.addListener(_redraw);
    _tick = Timer.periodic(_judgeEvery, (_) => _redraw());
    _fixArrived();
    if (widget.away) _goAway(true);
  }

  @override
  void didUpdateWidget(FollowCard old) {
    super.didUpdateWidget(old);
    if (old.journey != widget.journey) {
      _follower = _start();
      _progress = null;
      _watch = Watch();
      _caught = const Catch(CatchKind.ok);
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
    _tick.cancel();
    widget.here.removeListener(_fixArrived);
    widget.live.removeListener(_redraw);
    if (widget.away) _goAway(false);
    super.dispose();
  }

  Follower _start() => Follower(widget.journey, widget.catalog, widget.stage);

  /// Whether the next ride to board is still caught, from the latest arrivals
  void _judge() {
    final mps = widget.walkSpeed / _kmhPerMps;
    final hurryMps = max(widget.hurrySpeed ?? 0, widget.walkSpeed) / _kmhPerMps;
    int? due(int stop, int veh) =>
        widget.live.arrivals[stop]?.where((a) => a.veh == veh).firstOrNull?.t;
    final now = clock.now().millisecondsSinceEpoch / _msPerS;
    final reach = _follower.reach(due, now, mps, hurryMps);
    final said = _caught;
    _caught = _watch.update(reach, _follower.progress.stage, now);
    if (_caught.kind != said.kind || _caught.leg != said.leg) {
      widget.onCaught?.call(_caught);
    }
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
    return widget.catalog.routeAt(widget.journey.legs[p.stage.leg].route);
  }

  /// Repeats the card on the notification, sounding once for each moment
  /// worth taking the phone out for.
  void _notice() {
    final progress = _progress;
    if (!widget.away || progress == null) return;
    final said = _said(progress);
    final leg = progress.stage.leg;
    final caught = _caught;
    // Getting off soon is when a change ahead needing hurrying shows up
    final moments = [
      ?switch (progress) {
        Progress(stage: Stage(kind: StageKind.arrived)) => 'arrived',
        Progress(passed: true) => 'passed $leg',
        Progress(soon: true) => 'soon $leg',
        _ => null,
      },
      ?switch (caught.kind) {
        CatchKind.ok => null,
        CatchKind.hurry => 'hurry ${caught.leg} ${caught.riding}',
        CatchKind.missed => 'missed ${caught.leg}',
      },
    ];
    var alert = false;
    for (final m in moments) {
      alert = _alerted.add(m) || alert;
    }
    final line = [
      if (said.line.isNotEmpty) said.line,
      ?_catchSaid(widget.catalog, widget.journey, caught),
    ].join('\n');
    final text = '${said.head}\n$line';
    if (!alert && text == _noticed) return;
    _noticed = text;
    unawaited(widget.here.notice(said.head, line, alert: alert));
  }

  /// The arrivals or the time moved on, so the times said are redrawn.
  void _redraw() {
    setState(_judge);
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
    final at = _follower.progress.stage;
    setState(() {
      _progress = _follower.update(
        Fix(
          lat: fix.point.latitude,
          lon: fix.point.longitude,
          accuracy: fix.accuracy,
          t: fix.t,
        ),
        seen,
      );
      _judge();
    });
    widget.onProgress?.call(_follower.progress);
    final stage = _follower.progress.stage;
    if (stage != at) widget.onMoved(stage);
    _notice();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final done = progress?.stage.kind == StageKind.arrived;
    final faint = material.Theme.of(context).textTheme.bodySmall;
    // Back folds the steps first: the card is on the map, where back would
    // otherwise leave the app
    return PopScope(
      canPop: !_steps,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _steps = false);
      },
      child: Floating(
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
              if (!done && (progress?.astray ?? false))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => widget.onRebuild(progress!.stage),
                    child: Text(txt.rebuildWay),
                  ),
                ),
              if (!done &&
                  widget.updatedAt != null &&
                  clock.now().millisecondsSinceEpoch ~/ 1000 -
                          widget.updatedAt! <
                      _updatedSaidS)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    txt.routeUpdated,
                    style: const TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ),
              if (!done && _caught.kind != CatchKind.ok)
                _CatchRow(
                  said: _catchSaid(widget.catalog, widget.journey, _caught)!,
                  missed: _caught.kind == CatchKind.missed,
                  kmh: _caught.kmh,
                  action: _caught.kind == CatchKind.missed
                      ? txt.planAgain
                      : _caught.riding
                      ? txt.findAnother
                      : null,
                  onTap: () => widget.onSearch(_follower.progress.stage),
                ),
              if (_steps)
                _Steps(
                  catalog: widget.catalog,
                  journey: widget.journey,
                  live: widget.live,
                  progress: progress,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The next ride to board caught only by hurrying, or missed, or null when
/// it is caught. Hurrying is urged only on foot; on a ride it is a warning.
String? _catchSaid(Catalog catalog, Journey journey, Catch caught) {
  if (caught.kind == CatchKind.ok) return null;
  final leg = journey.legs[caught.leg];
  final route = catalog.routeAt(leg.route)?.short ?? '';
  final stop = catalog.stopName(leg.a);
  if (caught.kind == CatchKind.missed) {
    return '${txt.noLonger}: ${txt.missedRide(route, stop)}';
  }
  return caught.riding
      ? txt.hurryAhead(route, stop)
      : txt.hurryNow(route, countdown(caught.dep.round()));
}

/// What the watch on the next connection says, with a way to find another
/// where there is one to offer
class _CatchRow extends StatelessWidget {
  const _CatchRow({
    required this.said,
    required this.missed,
    required this.kmh,
    required this.action,
    required this.onTap,
  });

  final String said;
  final bool missed;

  /// The pace hurrying needs, when it is asked for
  final double? kmh;
  final String? action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = material.Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.only(top: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: hair)),
      ),
      child: Row(
        children: [
          if (kmh case final kmh?) ...[
            HurryPill(text: txt.kmh(kmh), hint: txt.paceHint),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              said,
              style: theme.textTheme.bodySmall?.copyWith(
                color: missed ? theme.colorScheme.error : Colors.amber,
              ),
            ),
          ),
          if (action case final action?)
            TextButton(onPressed: onTap, child: Text(action)),
        ],
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
  String name(int stop) => catalog.stopName(stop);
  final String head;
  Arrival? when;
  int? walkArr;
  final now = clock.now().millisecondsSinceEpoch ~/ 1000;
  switch (stage.kind) {
    case StageKind.walk:
      head = leg.b < 0 ? txt.walkHome : txt.walkTo(name(leg.b));
      // When the metres left get there, at the pace the walk was planned at
      walkArr = now + walkRest(leg, progress.left).round();
    case StageKind.wait:
      // The planned vehicle on its current trip, or the route's next one
      head = txt.waitAt(name(leg.a));
      when = leavingAt(
        live.arrivals[leg.a] ?? const <Arrival>[],
        leg.route,
        leg.veh,
        now,
      );
    default:
      // Only the vehicle ridden says when it gets there; another of its
      // route could be the one ahead
      head = progress.soon ? txt.offSoon(name(leg.b)) : txt.offAt(name(leg.b));
      when = stage.veh == null
          ? null
          : arrivalOf(
              live.arrivals[leg.b] ?? const <Arrival>[],
              stage.veh!,
              leg.dep,
            );
  }
  final sub = stage.kind == StageKind.wait
      ? (when == null ? null : txt.dueIn(countdown(when.t)))
      : [
          txt.toGo(_distance(progress.left)),
          if (walkArr != null) clockTime(walkArr),
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
                maxLines: _headLines,
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
    required this.live,
    required this.progress,
  });

  final Catalog catalog;
  final Journey journey;
  final Live live;

  /// Where the journey is, or null while that is not known
  final Progress? progress;

  @override
  Widget build(BuildContext context) {
    final stage = progress?.stage;
    // Every time still to come is worked out from the predictions and how far
    // along the device is, so a step never claims to end at a time gone by
    final list = liveRows(
      journey,
      LivePlan(
        now: clock.now().millisecondsSinceEpoch ~/ 1000,
        stage: stage,
        left: progress?.left ?? 0,
        arrivals: live.arrivals,
      ),
    );
    final now = stage == null ? -1 : current(list, stage);
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
    String name(int stop) => catalog.stopName(stop);
    final route = catalog.routeAt(row.route);
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

String _distance(double m) => m < _mPerKm
    ? txt.metres((m / _stepM).round() * _stepM)
    : txt.km(m / _mPerKm);
