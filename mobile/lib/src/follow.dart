/// Following a journey as it is travelled, from the device's own fixes. Nothing
/// here leaves the device: the fixes are compared against the journey's legs
/// and the vehicles the socket already sends. `web/src/lib/follow.ts` is the
/// same machine, and these tests are its tests too.
///
/// Boarding is the step that has to be right. Standing at a stop beside a tram
/// looks exactly like sitting in it, so a ride counts as boarded only once the
/// fixes move along the ride's line faster than anyone walks. Only then is the
/// vehicle picked: the one of the leg's route keeping pace with the fixes.
///
/// Ahead of every ride still to board, the fixes and the predictions say
/// whether it is still caught: walking to its stop at the usual pace, only by
/// hurrying - now, or off the ride before it - or not at all.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'models.dart';

class Fix {
  const Fix({
    required this.lat,
    required this.lon,
    required this.accuracy,
    required this.t,
  });

  final double lat;
  final double lon;
  final double accuracy;

  /// Milliseconds
  final int t;
}

/// A vehicle where the map draws it at the time of the fix
class Seen {
  const Seen({
    required this.id,
    required this.route,
    required this.lat,
    required this.lon,
  });

  final int id;
  final int route;
  final double lat;
  final double lon;
}

enum StageKind { walk, wait, ride, arrived }

class Stage {
  const Stage(this.kind, [this.leg = -1, this.veh]);

  factory Stage.fromJson(Map<String, dynamic> j) => Stage(
    StageKind.values.byName(j['kind'] as String),
    j['leg'] as int? ?? -1,
    j['veh'] as int?,
  );

  final StageKind kind;
  final int leg;

  /// The wire id of the vehicle ridden, null while none keeps pace
  final int? veh;

  Map<String, Object?> toJson() => {'kind': kind.name, 'leg': leg, 'veh': veh};

  @override
  bool operator ==(Object other) =>
      other is Stage &&
      other.kind == kind &&
      other.leg == leg &&
      other.veh == veh;

  @override
  int get hashCode => Object.hash(kind, leg, veh);
}

/// When a vehicle gets to a stop, unix seconds, while the predictions say
typedef Due = int? Function(int stop, int veh);

/// When the next ride to board leaves, and when the device gets to its stop
/// at the usual and at the hurrying pace, all unix seconds: setting off on foot
/// at [from] for the [walk] metres there. [live]: [dep] is a prediction for a
/// tracked vehicle, not the timetable.
class Reach {
  const Reach({
    required this.leg,
    required this.dep,
    required this.live,
    required this.from,
    required this.walk,
    required this.usual,
    required this.hurried,
  });

  final int leg;
  final double dep;
  final bool live;
  final double from;
  final double walk;
  final double usual;
  final double hurried;
}

enum CatchKind { ok, hurry, missed }

/// The next ride to board, on time or not: [riding] warns ahead of a change
/// from the ride under way, which hurrying cannot help yet. [kmh] is the pace
/// hurrying needs ([needKmh]), null once missed.
class Catch {
  const Catch(
    this.kind, [
    this.leg = -1,
    this.dep = 0,
    this.riding = false,
    this.kmh,
  ]);

  final CatchKind kind;
  final int leg;
  final double dep;
  final bool riding;
  final double? kmh;
}

/// A tracked vehicle missed by this little is still caught: the driver waits
/// for somebody waving or running. `GRACE` in `commuterlviv/plan/scan.py`.
const graceS = 10.0;

/// Seconds ahead, and the slack a change needs that far ahead: `CHANGE_AHEAD`
/// and `CHANGE_SLACK` in `commuterlviv/plan/scan.py`
const _changeAhead = <double>[60, 210, 450, 750, 1050, 1500, 2250];
const _changeSlack = <double>[60, 90, 150, 180, 210, 270, 300];

/// A change is broken by either vehicle's forecast missing, a walk to a stop
/// only by the one vehicle's, so it keeps this share of a change's slack.
/// Chosen, not derived
const _marginShare = 0.5;
const _kmhPerMps = 3.6;

/// A worse word on the connection holds this long before it is said: two of
/// the service's five-second frames, so one jumpy prediction is not news.
/// Chosen, not derived.
const _holdS = 10.0;

/// Closer to leaving than this a prediction is good to some 22 s
/// (docs/service.md), so a worse word is said at once
const _nearS = 120.0;

class Progress {
  const Progress({
    required this.stage,
    required this.left,
    required this.astray,
    required this.passed,
    required this.soon,
  });

  final Stage stage;

  /// Metres still to go on the current leg, along it
  final double left;

  /// Further from the leg's line than a fix's error explains
  final bool astray;

  /// Carried on past the stop to get off at
  final bool passed;

  /// On the ride, past its last stop before the one to get off at
  final bool soon;
}

/// A fix vaguer than this says nothing about which side of a tram it is on
const _maxAccuracyM = 50.0;

/// Close enough to a stop or the door to be at it
const _arriveM = 40.0;

/// How far from a leg's line a fix on it can still land
const _onLineM = 50.0;

/// Further than this off the line is off the journey
const _astrayM = 100.0;

/// A brisk walk or a jog, but no vehicle in motion
const _walkMaxMps = 2.5;

/// Ridden this far along the line, faster than walking, is boarded
const _boardM = 100.0;

/// Fixes it takes to believe that, so one jump of the GPS is not a ride
const _boardFixes = 3;

/// A vehicle further than this along the line from the fixes is another one.
/// Generous: the map draws a vehicle from its last fix, 10 s old at median, and
/// dead-reckons only part of the way on from there.
const _matchM = 150.0;

/// The share of the fixes' way along the line a vehicle must have gone too,
/// over the same fixes, to be the one carrying them. Its drawn position moves
/// in a step per frame, so this asks for less than all of it.
const _paceShare = 0.5;

/// A vehicle this far from the ride's line is not on it
const _vehicleOffM = 60.0;

/// Fixes in a row the ridden vehicle may fall out of step before another is
/// looked for
const _lostFixes = 5;

/// Moving no faster than walking for this long, at the stop, is off
const _alightS = 15;

/// This far beyond the stop, faster than walking, is carried past it
const _passedM = 150.0;

/// Where a ride does not say which stops it calls at, this close to the stop
/// to get off at is getting ready for it. Chosen, not derived: about a stop's
/// spacing in the city centre.
const _soonM = 400.0;

/// What is kept of the fixes: enough for [_boardM] at walking pace
const _historyMs = 60000;

const _earthM = 6371000.0;
const _rad = math.pi / 180;

typedef _XY = ({double x, double y});

/// Where a fix and a vehicle seen with it were, in metres along a line
typedef _Beside = ({double user, double veh});

double _dist(_XY a, _XY b) => math.sqrt(_sq(a.x - b.x) + _sq(a.y - b.y));

double _sq(double v) => v * v;

/// Flat metres around [lat0], [lon0], which over a city is exact enough
_XY Function(double lat, double lon) _plane(double lat0, double lon0) {
  final kx = _earthM * _rad * math.cos(lat0 * _rad);
  const ky = _earthM * _rad;
  return (lat, lon) => (x: (lon - lon0) * kx, y: (lat - lat0) * ky);
}

class _Line {
  _Line(this.xy) {
    for (var i = 1; i < xy.length; i++) {
      cum.add(cum[i - 1] + _dist(xy[i - 1], xy[i]));
    }
  }

  final List<_XY> xy;
  final List<double> cum = [0];

  double get length => cum.last;
  _XY get end => xy.last;

  /// Metres along the line to the point nearest [p], and how far off it [p] is
  ({double s, double off}) project(_XY p) {
    if (xy.length == 1) return (s: 0, off: _dist(p, xy[0]));
    var best = (s: 0.0, off: double.infinity);
    for (var i = 1; i < xy.length; i++) {
      final a = xy[i - 1], b = xy[i];
      final dx = b.x - a.x, dy = b.y - a.y;
      final len2 = dx * dx + dy * dy;
      final k = len2 == 0
          ? 0.0
          : (((p.x - a.x) * dx + (p.y - a.y) * dy) / len2).clamp(0.0, 1.0);
      final off = math.sqrt(_sq(p.x - a.x - k * dx) + _sq(p.y - a.y - k * dy));
      if (off < best.off) {
        best = (s: cum[i - 1] + k * math.sqrt(len2), off: off);
      }
    }
    return best;
  }
}

class _Sample {
  _Sample(this.t, this.at, this.seen);

  final int t;
  final _XY at;
  final List<({int id, int route, _XY at})> seen;
}

/// Every leg must carry its line; an older service sends none
bool followable(Journey j) => j.legs.every((l) => l.pts.isNotEmpty);

/// A journey begun on board starts on its ride, the rest walking or waiting
Stage start(Journey j) {
  final first = j.legs.firstOrNull;
  if (first == null || first.kind != 'ride') {
    return const Stage(StageKind.walk, 0);
  }
  return j.aboard
      ? Stage(StageKind.ride, 0, first.veh)
      : const Stage(StageKind.wait, 0);
}

class Follower {
  /// [catalog] places the stops a ride calls at; without it, or without them,
  /// getting ready goes by [_soonM]. [stage] resumes a journey followed before.
  Follower(Journey journey, [Catalog? catalog, Stage? stage])
    : _legs = journey.legs {
    final o = _legs.first.pts.first;
    _at = _plane(o.latitude, o.longitude);
    _lines = [
      for (final l in _legs)
        _Line([for (final p in l.pts) _at(p.latitude, p.longitude)]),
    ];
    _routes = {
      for (final l in _legs)
        if (l.route != null) l.route!,
    };
    _ready = [
      for (final (i, l) in _legs.indexed) _readyAt(l, _lines[i], catalog),
    ];
    _stage = stage ?? start(journey);
    _last = Progress(
      stage: _stage,
      left: _stage.kind == StageKind.arrived ? 0 : _lines[_stage.leg].length,
      astray: false,
      passed: false,
      soon: false,
    );
  }

  final List<Leg> _legs;
  late final _XY Function(double lat, double lon) _at;
  late final List<_Line> _lines;
  late final Set<int> _routes;

  /// Metres along each leg from which it is time to get ready to get off
  late final List<double> _ready;
  late Stage _stage;
  var _history = <_Sample>[];

  /// Fixes in a row the ridden vehicle has been out of step
  var _misses = 0;

  /// Got within [_arriveM] of the ride's last stop
  var _reached = false;
  late Progress _last;

  Progress get progress => _last;

  _Sample get _now => _history.last;

  /// Reaching the stop before the one to get off at - the boarding stop, for a
  /// ride of one stop - or else [_soonM] short of the end
  double _readyAt(Leg leg, _Line line, Catalog? catalog) {
    final stops = leg.stops;
    if (catalog == null || stops == null) return line.length - _soonM;
    final s = catalog.stops[stops.isEmpty ? leg.a : stops.last];
    return line.project(_at(s.lat, s.lon)).s - _arriveM;
  }

  /// When the next ride to board leaves and when the device gets to its stop,
  /// at [mps] and at [hurryMps] metres a second. Null with no ride ahead,
  /// while waiting at its stop - the vehicle is in sight there - and while the
  /// vehicle ridden is not known or not predicted to the stop to get off at.
  Reach? reach(Due due, double now, double mps, double hurryMps) {
    final stage = _stage;
    if (stage.kind == StageKind.wait || stage.kind == StageKind.arrived) {
      return null;
    }
    var r = -1;
    for (var k = stage.leg + 1; k < _legs.length && r < 0; k++) {
      if (_legs[k].kind == 'ride') r = k;
    }
    if (r < 0) return null;
    var from = now;
    var walk = 0.0;
    if (stage.kind == StageKind.walk) {
      walk = _last.left;
    } else {
      final off = stage.veh == null
          ? null
          : due(_legs[stage.leg].b, stage.veh!);
      if (off == null) return null;
      from = off.toDouble();
    }
    for (var k = stage.leg + 1; k < r; k++) {
      walk += _lines[k].length;
    }
    final next = _legs[r];
    final tracked = next.veh == null ? null : due(next.a, next.veh!);
    return Reach(
      leg: r,
      dep: (tracked ?? next.dep).toDouble(),
      live: tracked != null,
      from: from,
      walk: walk,
      usual: from + walk / mps,
      hurried: from + walk / hurryMps,
    );
  }

  /// Takes a fix and the vehicles drawn at its time, and says where on the
  /// journey that puts the device. A vague fix changes nothing, and nor does
  /// one older than the last: a phone's two sources of fixes interleave.
  Progress update(Fix fix, List<Seen> vehicles) {
    if (fix.accuracy > _maxAccuracyM ||
        _stage.kind == StageKind.arrived ||
        (_history.isNotEmpty && fix.t <= _now.t)) {
      return _last;
    }
    _history.add(
      _Sample(fix.t, _at(fix.lat, fix.lon), [
        for (final v in vehicles)
          if (_routes.contains(v.route))
            (id: v.id, route: v.route, at: _at(v.lat, v.lon)),
      ]),
    );
    _history = [
      for (final h in _history)
        if (fix.t - h.t <= _historyMs) h,
    ];
    var passed = false;
    switch (_stage.kind) {
      case StageKind.walk:
        passed = _walk(_stage.leg);
      case StageKind.wait:
        _board(_stage.leg);
      case StageKind.ride || StageKind.arrived:
        passed = _ride(_stage.leg, _stage.veh);
    }
    return _last = _report(passed);
  }

  Progress _report(bool passed) {
    if (_stage.kind == StageKind.arrived) {
      return Progress(
        stage: _stage,
        left: 0,
        astray: false,
        passed: false,
        soon: false,
      );
    }
    final line = _lines[_stage.leg];
    final p = line.project(_now.at);
    return Progress(
      stage: _stage,
      left: math.max(0, line.length - p.s),
      astray: p.off > _astrayM,
      passed: passed,
      soon: _stage.kind == StageKind.ride && p.s >= _ready[_stage.leg],
    );
  }

  void _go(Stage stage) {
    _stage = stage;
    // What was seen on one leg proves nothing about the next, except that a
    // walk to a stop may already be the ride from it
    if (stage.kind != StageKind.wait) _history = [_now];
    _misses = 0;
    _reached = false;
  }

  /// The leg after [i], as the stage that starts it
  Stage _next(int i) {
    if (i + 1 >= _legs.length) return const Stage(StageKind.arrived);
    return _legs[i + 1].kind == 'ride'
        ? Stage(StageKind.wait, i + 1)
        : Stage(StageKind.walk, i + 1);
  }

  bool _walk(int i) {
    final ride = i + 1 < _legs.length && _legs[i + 1].kind == 'ride';
    // A walk ending at a stop may turn into the ride before the fixes ever
    // came within [_arriveM] of it
    if (ride && _board(i + 1)) return false;
    if (_dist(_now.at, _lines[i].end) <= _arriveM) {
      _go(_next(i));
      return false;
    }
    return i > 0 && _legs[i - 1].kind == 'ride' && _brisk(i);
  }

  /// Whether the fixes have ridden away along leg [i]'s line; if so the stage
  /// is the ride, on the vehicle that kept pace if one did
  bool _board(int i) {
    final line = _lines[i];
    final along = [for (final h in _history) (h: h, p: line.project(h.at))];
    final last = along.last;
    // The latest fix still behind by [_boardM], it and everything after it on
    // the line
    var from = -1;
    for (var k = along.length - 1; k >= 0; k--) {
      if (along[k].p.off > _onLineM) break;
      if (last.p.s - along[k].p.s >= _boardM) {
        from = k;
        break;
      }
    }
    if (from < 0 || along.length - from < _boardFixes) return false;
    final took = (last.h.t - along[from].h.t) / 1000;
    if (took <= 0 || _boardM / took <= _walkMaxMps) return false;
    final veh = _pace(line, _legs[i], _history.sublist(from));
    _go(Stage(StageKind.ride, i, veh));
    return true;
  }

  /// The vehicle of the leg's route keeping pace with these fixes: the one
  /// whose median gap along the line is smallest, within [_matchM]. The
  /// vehicle the plan named wins whenever it qualifies.
  int? _pace(_Line line, Leg leg, List<_Sample> samples) {
    final tracks = <int, List<_Beside>>{};
    for (final h in samples) {
      final s = line.project(h.at).s;
      for (final v in h.seen) {
        if (v.route != leg.route) continue;
        final p = line.project(v.at);
        if (p.off > _vehicleOffM) continue;
        (tracks[v.id] ??= []).add((user: s, veh: p.s));
      }
    }
    int? best;
    var bestGap = _matchM;
    for (final MapEntry(key: id, value: track) in tracks.entries) {
      if (!_keepsUp(track, samples.length)) continue;
      final gap = _median([for (final b in track) (b.veh - b.user).abs()]);
      if (gap > _matchM) continue;
      if (id == leg.veh) return id;
      if (gap <= bestGap) {
        best = id;
        bestGap = gap;
      }
    }
    return best;
  }

  /// Seen beside at least half the fixes, and gone at least [_paceShare] as
  /// far along the line as they did. A tram left standing at the stop is close
  /// to the first fixes of a ride on the next one, and only this tells them
  /// apart.
  static bool _keepsUp(List<_Beside> track, int fixes) {
    if (track.length * 2 < fixes) return false;
    final user = track.last.user - track.first.user;
    return track.last.veh - track.first.veh >= user * _paceShare;
  }

  bool _ride(int i, int? veh) {
    final line = _lines[i];
    final here = line.project(_now.at).s;
    final v = veh == null
        ? null
        : _now.seen.where((x) => x.id == veh).firstOrNull;
    // The route too: a pruned vehicle's id can come back on another one
    final inStep =
        v != null &&
        v.route == _legs[i].route &&
        (line.project(v.at).s - here).abs() <= _matchM;
    _misses = inStep ? 0 : _misses + 1;
    if (_misses >= _lostFixes) {
      _stage = Stage(StageKind.ride, i, _pace(line, _legs[i], _history));
      _misses = 0;
    }
    final gap = _dist(_now.at, line.end);
    if (gap <= _arriveM) _reached = true;
    if (_reached && gap <= _arriveM && _still()) {
      _go(_next(i));
      return false;
    }
    return _reached && gap > _passedM;
  }

  /// No faster than walking over the last [_alightS]
  bool _still() {
    final now = _now;
    for (var k = _history.length - 1; k >= 0; k--) {
      final h = _history[k];
      final took = (now.t - h.t) / 1000;
      if (took >= _alightS) return _dist(now.at, h.at) <= _walkMaxMps * took;
    }
    return false;
  }

  /// Away from the walk's start by [_passedM], faster than walking: still on
  /// the vehicle that should have been left there
  bool _brisk(int i) {
    final startAt = _lines[i].xy.first;
    final now = _now;
    final away = _dist(now.at, startAt);
    if (away < _passedM) return false;
    for (final h in _history.reversed) {
      final took = (now.t - h.t) / 1000;
      if (took > 0 && away - _dist(h.at, startAt) >= _passedM) {
        return _passedM / took > _walkMaxMps;
      }
    }
    return false;
  }
}

double _median(List<double> xs) {
  final s = [...xs]..sort();
  final m = s.length >> 1;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

/// [xs] ascending; flat past both ends
double _interp(double x, List<double> xs, List<double> ys) {
  final k = xs.indexWhere((v) => v >= x);
  if (k == 0) return ys.first;
  if (k < 0) return ys.last;
  final share = (x - xs[k - 1]) / (xs[k] - xs[k - 1]);
  return ys[k - 1] + share * (ys[k] - ys[k - 1]);
}

/// Seconds to be at a stop before a vehicle forecast to leave [ahead] s from
/// now does, so that a forecast missing the usual amount still finds it there
double margin(double ahead) =>
    _marginShare * _interp(ahead, _changeAhead, _changeSlack);

/// The pace in km/h that walks [metres] setting off at [from] to be at the
/// stop [margin] before [dep], forecast at [now] - or right at [dep] should the
/// margin take more than a run (`hurryKmh.max`). Rounded up to the step speeds
/// are set in; null with nothing to walk, or when not even that leaves any
/// time.
double? needKmh(double metres, double from, double dep, [double? now]) {
  double pace(double s) => s > 0 ? metres / s * _kmhPerMps : double.infinity;
  var kmh = pace(dep - margin(dep - (now ?? from)) - from);
  if (kmh > hurryKmh.max) kmh = pace(dep - from);
  if (!kmh.isFinite || kmh <= 0) return null;
  return (kmh / hurryKmh.step).ceil() * hurryKmh.step;
}

/// Metres along [pts]
double along(List<LatLng> pts) {
  final o = pts.firstOrNull ?? const LatLng(0, 0);
  final at = _plane(o.latitude, o.longitude);
  return _Line([for (final p in pts) at(p.latitude, p.longitude)]).length;
}

/// [needKmh] of an option caught only by hurrying, as it was planned
double? plannedKmh(Journey j) {
  if (j.legs.length < 2) return null;
  final [walk, ride, ...] = j.legs;
  if (walk.kind != 'walk' || ride.kind != 'ride') return null;
  return needKmh(along(walk.pts), walk.dep.toDouble(), ride.dep.toDouble());
}

/// Caught at the usual pace; else at the hurrying one, or for a tracked
/// vehicle within [graceS] of it; else missed
CatchKind judge(Reach r) {
  if (r.usual <= r.dep) return CatchKind.ok;
  return r.hurried <= r.dep || (r.live && r.hurried - graceS <= r.dep)
      ? CatchKind.hurry
      : CatchKind.missed;
}

const _ok = Catch(CatchKind.ok);

/// What to say of the next connection, steadied: a better word is said at
/// once, a worse one only once it has held for [_holdS], or at once within
/// [_nearS] of leaving
class Watch {
  Catch _said = _ok;

  /// A worse word than the one said, and since when it has held
  ({CatchKind kind, int leg, double since})? _coming;

  /// [reach] is the follower's answer at [stage], [now] unix seconds
  Catch update(Reach? reach, Stage stage, double now) {
    final said = _said;
    if (reach == null) {
      // Waiting at the stop of a connection missed still has it missed: the
      // vehicle there is a later one
      final missed =
          said.kind == CatchKind.missed &&
          stage.kind == StageKind.wait &&
          stage.leg == said.leg;
      _said = missed ? said : _ok;
      _coming = null;
      return _said;
    }
    if (said.kind != CatchKind.ok && said.leg != reach.leg) _said = _ok;
    final kind = judge(reach);
    final kmh = kind == CatchKind.hurry
        ? needKmh(reach.walk, reach.from, reach.dep, now)
        : null;
    final word = kind == CatchKind.ok
        ? _ok
        : Catch(kind, reach.leg, reach.dep, stage.kind == StageKind.ride, kmh);
    if (kind.index <= _said.kind.index) {
      _said = word;
      _coming = null;
      return word;
    }
    final coming = _coming;
    if (coming == null || coming.kind != kind || coming.leg != reach.leg) {
      _coming = (kind: kind, leg: reach.leg, since: now);
    }
    if (now - _coming!.since >= _holdS || reach.dep - now <= _nearS) {
      _said = word;
      _coming = null;
    }
    return _said;
  }
}
