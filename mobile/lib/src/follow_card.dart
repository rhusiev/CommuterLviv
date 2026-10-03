/// What to do now on a journey being followed, from the bottom of the map.
library;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;

import 'eta.dart';
import 'follow.dart';
import 'here.dart' show Here, Locating;
import 'live.dart';
import 'models.dart';
import 'route_badge.dart';
import 'strings.dart';
import 'theme.dart';

/// Closer than this to the stop to get off at, the card says to get ready.
/// Chosen, not derived: about a stop's spacing in the city centre.
const _soonM = 400;

const _mPerKm = 1000;

/// Short distances are said to this many metres
const _stepM = 10;

/// Follows [journey] from [here]'s fixes for as long as it is mounted. The
/// fixes go nowhere but the follower.
class FollowCard extends StatefulWidget {
  const FollowCard({
    super.key,
    required this.catalog,
    required this.journey,
    required this.live,
    required this.here,
    required this.onEnd,
  });

  final Catalog catalog;
  final Journey journey;
  final Live live;
  final Here here;
  final VoidCallback onEnd;

  @override
  State<FollowCard> createState() => _FollowCardState();
}

class _FollowCardState extends State<FollowCard> {
  late Follower _follower = Follower(widget.journey);
  Progress? _progress;

  @override
  void initState() {
    super.initState();
    widget.here.addListener(_fixArrived);
    widget.live.addListener(_redraw);
    _fixArrived();
  }

  @override
  void didUpdateWidget(FollowCard old) {
    super.didUpdateWidget(old);
    if (old.journey != widget.journey) {
      _follower = Follower(widget.journey);
      _progress = null;
    }
    if (old.here != widget.here) {
      old.here.removeListener(_fixArrived);
      widget.here.addListener(_fixArrived);
    }
    if (old.live != widget.live) {
      old.live.removeListener(_redraw);
      widget.live.addListener(_redraw);
    }
  }

  @override
  void dispose() {
    widget.here.removeListener(_fixArrived);
    widget.live.removeListener(_redraw);
    super.dispose();
  }

  /// The arrivals moved on, so the times said are redrawn.
  void _redraw() => setState(() {});

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
        child: Row(
          children: [
            Expanded(
              child: progress != null
                  ? _Step(
                      catalog: widget.catalog,
                      journey: widget.journey,
                      live: widget.live,
                      progress: progress,
                    )
                  : widget.here.state == Locating.denied
                  ? Text(
                      txt.noLocation,
                      style: TextStyle(
                        color: material.Theme.of(context).colorScheme.error,
                      ),
                    )
                  : Text(txt.locating, style: faint),
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
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.catalog,
    required this.journey,
    required this.live,
    required this.progress,
  });

  final Catalog catalog;
  final Journey journey;
  final Live live;
  final Progress progress;

  @override
  Widget build(BuildContext context) {
    final theme = material.Theme.of(context);
    final stage = progress.stage;
    if (stage.kind == StageKind.arrived) {
      return Text(txt.arrived, style: theme.textTheme.titleSmall);
    }
    final leg = journey.legs[stage.leg];
    final route = leg.route == null ? null : catalog.routes[leg.route!];
    String name(int stop) => catalog.stops[stop].name;
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
        head = progress.left <= _soonM
            ? txt.offSoon(name(leg.b))
            : txt.offAt(name(leg.b));
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (stage.kind != StageKind.walk && route != null) ...[
              RouteBadge(route: route, fontSize: 10),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                head,
                style: theme.textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (sub != null) Text(sub, style: theme.textTheme.bodySmall),
        if (progress.passed)
          Text(
            txt.passedStop,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          )
        else if (progress.astray)
          Text(
            txt.offTheWay,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.amber),
          ),
      ],
    );
  }
}

String _distance(double m) => m < _mPerKm
    ? txt.metres((m / _stepM).round() * _stepM)
    : txt.km(m / _mPerKm);
