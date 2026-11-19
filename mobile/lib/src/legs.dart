import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'follow.dart';
import 'models.dart';

enum PlanRowKind { walk, wait, ride }

/// One line of a journey's plan: a leg, or the wait at a stop before a ride.
class PlanRow {
  const PlanRow(
    this.kind,
    this.leg, {
    required this.dep,
    required this.arr,
    required this.a,
    required this.b,
    this.route,
    this.change = false,
  });

  final PlanRowKind kind;

  /// The journey leg it belongs to, the ride waited for on a wait
  final int leg;
  final int dep;
  final int arr;

  /// The stops it is from and to, -1 for the door; a wait's are both the stop
  final int a;
  final int b;
  final int? route;

  /// A walk between two rides
  final bool change;
}

/// A shorter gap before a ride is not worth a line of its own
const waitMinS = 60;

/// The seconds between leg [i] leaving and the leg before it arriving: the wait
/// at the stop when [i] is a ride. Nothing comes before the first leg
int waitBefore(Journey j, int i) =>
    i > 0 ? j.legs[i].dep - j.legs[i - 1].arr : 0;

/// The journey's legs in order, with a wait wherever a ride leaves a minute or
/// more after the leg before it got there
List<PlanRow> rows(Journey j) => rowsOf(j.legs);

/// [rows] of legs already carrying their times
List<PlanRow> rowsOf(List<Leg> legs) {
  final out = <PlanRow>[];
  for (final (i, leg) in legs.indexed) {
    if (leg.kind == 'walk') {
      // Consecutive walks are folded before they are sent, so a walk with a
      // ride either side is the change itself
      final change = leg.b >= 0 && i > 0 && i < legs.length - 1;
      out.add(
        PlanRow(
          PlanRowKind.walk,
          i,
          dep: leg.dep,
          arr: leg.arr,
          a: leg.a,
          b: leg.b,
          change: change,
        ),
      );
      continue;
    }
    if (i > 0 && leg.dep - legs[i - 1].arr >= waitMinS) {
      out.add(
        PlanRow(
          PlanRowKind.wait,
          i,
          dep: legs[i - 1].arr,
          arr: leg.dep,
          a: leg.a,
          b: leg.a,
        ),
      );
    }
    out.add(
      PlanRow(
        PlanRowKind.ride,
        i,
        dep: leg.dep,
        arr: leg.arr,
        a: leg.a,
        b: leg.b,
        route: leg.route,
      ),
    );
  }
  return out;
}

const _rowOf = {
  StageKind.walk: PlanRowKind.walk,
  StageKind.wait: PlanRowKind.wait,
  StageKind.ride: PlanRowKind.ride,
};

/// The row [stage] is at: its own kind on its leg, else the leg's last row -
/// the ride, when its wait was too short to list. -1 once arrived
int current(List<PlanRow> list, Stage stage) {
  final kind = _rowOf[stage.kind];
  if (kind == null) return -1;
  final same = list.indexWhere((r) => r.leg == stage.leg && r.kind == kind);
  if (same >= 0) return same;
  final next = list.indexWhere((r) => r.leg > stage.leg);
  return (next < 0 ? list.length : next) - 1;
}

/// The vehicles a journey's rides are planned on.
Set<int> riddenBy(Journey? journey) => {
  for (final leg in journey?.legs ?? const <Leg>[]) ?leg.veh,
};

/// What a followed plan's times are worked out from, all of it already on the
/// device
class LivePlan {
  const LivePlan({
    required this.now,
    required this.stage,
    required this.left,
    required this.arrivals,
  });

  /// Unix seconds
  final int now;

  /// Where the follower is, or null while that is not known
  final Stage? stage;

  /// Metres left on the leg under way
  final double left;

  /// Predicted arrivals by catalog stop index, as the socket sends them
  final Map<int, List<Arrival>> arrivals;
}

/// A vehicle is still the planned one this long after the walk was to get in:
/// the plans keep a margin, and a rider may catch it waving. `graceS` in
/// `follow.dart`
const _boardGraceS = 10;

/// The service's walking pace on the level, m/s: `SPEED` in `walk.py`
const _flatMps = 1.25;

/// [rows] of the followed journey with every time still to come taken from
/// live predictions and how far along the device is; the legs done keep the
/// times they were planned with. Nothing here asks the service.
List<PlanRow> liveRows(Journey j, LivePlan plan) => rowsOf(liveLegs(j, plan));

/// The followed journey's legs with their times still to come made live, as
/// [liveRows] describes.
List<Leg> liveLegs(Journey j, LivePlan plan) {
  final stage = plan.stage;
  if (stage == null || stage.kind == StageKind.arrived) return j.legs;
  List<Arrival> at(int stop) => plan.arrivals[stop] ?? const <Arrival>[];
  final out = <Leg>[];
  // When the leg before the one being built gets in
  var inAt = plan.now;
  for (var i = 0; i < j.legs.length; i++) {
    final leg = j.legs[i];
    if (i < stage.leg) {
      out.add(leg);
      inAt = leg.arr;
      continue;
    }
    if (leg.kind == 'walk') {
      final arr = i == stage.leg
          ? plan.now + walkRest(leg, plan.left).round()
          : inAt + _planned(leg);
      out.add(
        i == stage.leg
            ? leg.copyWith(arr: arr)
            : leg.copyWith(dep: inAt, arr: arr),
      );
      inAt = arr;
      continue;
    }
    // A ride under way keeps when it was boarded; only its arrival moves
    if (i == stage.leg) {
      final veh = stage.kind == StageKind.ride ? stage.veh : null;
      final arr = veh == null
          ? leg.arr
          : (_arrivalAt(at(leg.b), veh) ?? leg.arr);
      out.add(leg.copyWith(arr: arr));
      inAt = arr;
      continue;
    }
    final leaving = _leavingAt(at(leg.a), leg.route, leg.veh, inAt);
    final dep = leaving?.t ?? math.max(leg.dep, inAt);
    final arr = leaving == null
        ? dep + _planned(leg)
        : (_arrivalAt(at(leg.b), leaving.veh) ?? dep + _planned(leg));
    out.add(leg.copyWith(dep: dep, arr: arr));
    inAt = arr;
  }
  return out;
}

/// Seconds the rest of [leg] takes at the pace it was planned at. The service
/// times a walk over the footpaths, slopes and all, so its own seconds are kept
/// and shared out by distance rather than assumed flat.
double walkRest(Leg leg, double left) {
  final planned = _planned(leg).toDouble();
  final length = along(leg.pts);
  // Without a line to share the planned seconds along, the service's own pace
  // is all there is to go by; a service that sends no line cannot be followed
  if (length <= 0) return left / _flatMps;
  return planned * math.min(1, math.max(0, left / length));
}

int _planned(Leg leg) => math.max(0, leg.arr - leg.dep);

int? _arrivalAt(List<Arrival> list, int veh) =>
    list.where((a) => a.veh == veh).firstOrNull?.t;

/// The arrival of [route] to leave at or after [from], preferring the planned
/// vehicle [veh] whenever it is still catchable
Arrival? _leavingAt(List<Arrival> list, int? route, int? veh, int from) {
  if (route == null) return null;
  final ofRoute = list.where((a) => a.route == route);
  if (veh != null) {
    for (final a in ofRoute) {
      if (a.veh == veh && a.t >= from - _boardGraceS) return a;
    }
  }
  for (final a in ofRoute) {
    if (a.t >= from) return a;
  }
  for (final a in ofRoute) {
    if (a.t >= from - _boardGraceS) return a;
  }
  return null;
}

/// How much sooner a plan that still works must arrive to be followed instead:
/// chosen, not derived - enough to matter, not so little that a jumping
/// prediction moves the rider
const betterS = 120;

/// [options] with the one to follow in place of a plan arriving at
/// [currentArr]: the best the planner offers when the plan is [broken], else
/// one reaching the door at least [betterS] sooner. Null when the plan still
/// is the best.
Journey? betterPlan(int currentArr, List<Journey> options, bool broken) {
  final first = options.firstOrNull;
  if (first == null) return null;
  if (broken) return first;
  return first.arr <= currentArr - betterS ? first : null;
}

/// Whether [b] is the plan [a] already is, so following it would change
/// nothing
bool samePlan(Journey a, Journey b) {
  if (a.dep != b.dep || a.arr != b.arr || a.legs.length != b.legs.length) {
    return false;
  }
  for (var i = 0; i < a.legs.length; i++) {
    final l = a.legs[i];
    final o = b.legs[i];
    if (l.kind != o.kind ||
        l.a != o.a ||
        l.b != o.b ||
        l.route != o.route ||
        l.dep != o.dep ||
        l.arr != o.arr) {
      return false;
    }
  }
  return true;
}

/// The journey as it is under way, for the map: the legs already done left
/// off, and a walk under way, unless strayed from, drawn from [here] at [now]
/// (Unix seconds). Arrived, it is left whole.
Journey underWay(Journey j, Progress progress, LatLng here, int now) {
  final stage = progress.stage;
  if (stage.kind == StageKind.arrived) return j;
  final legs = j.legs.sublist(stage.leg);
  if (stage.kind == StageKind.walk && !progress.astray) {
    legs[0] = _walkingFrom(legs[0], progress.left, here, now);
  }
  return Journey(
    dep: j.dep,
    arr: j.arr,
    rides: j.rides,
    live: j.live,
    confidence: j.confidence,
    legs: legs,
    backup: j.backup,
    aboard: j.aboard,
    hurry: j.hurry,
  );
}

/// A walk drawn from [here] along the last [left] metres of its line, setting
/// off at [now].
Leg _walkingFrom(Leg leg, double left, LatLng here, int now) {
  const distance = Distance();
  final rest = <LatLng>[];
  var gone = 0.0;
  for (var i = leg.pts.length - 1; i > 0; i--) {
    rest.insert(0, leg.pts[i]);
    gone += distance(leg.pts[i], leg.pts[i - 1]);
    if (gone >= left) break;
  }
  return Leg(
    kind: leg.kind,
    dep: now < leg.arr ? now : leg.arr,
    arr: leg.arr,
    a: leg.a,
    b: leg.b,
    route: leg.route,
    veh: leg.veh,
    live: leg.live,
    confidence: leg.confidence,
    pts: [here, ...rest],
    stops: leg.stops,
    backups: leg.backups,
  );
}
