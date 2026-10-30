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
List<PlanRow> rows(Journey j) {
  final out = <PlanRow>[];
  for (final (i, leg) in j.legs.indexed) {
    if (leg.kind == 'walk') {
      // Consecutive walks are folded before they are sent, so a walk with a
      // ride either side is the change itself
      final change = leg.b >= 0 && i > 0 && i < j.legs.length - 1;
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
    if (waitBefore(j, i) >= waitMinS) {
      out.add(
        PlanRow(
          PlanRowKind.wait,
          i,
          dep: j.legs[i - 1].arr,
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

/// The journey as it is being walked: the walk under way drawn from [here],
/// along the last `left` metres of its line, setting off at [now] (Unix
/// seconds). Every other stage, and a walk strayed from, leaves it as planned.
Journey walkingFrom(Journey j, Progress progress, LatLng here, int now) {
  final stage = progress.stage;
  if (stage.kind != StageKind.walk || progress.astray) return j;
  final leg = j.legs[stage.leg];
  const distance = Distance();
  final rest = <LatLng>[];
  var gone = 0.0;
  for (var i = leg.pts.length - 1; i > 0; i--) {
    rest.insert(0, leg.pts[i]);
    gone += distance(leg.pts[i], leg.pts[i - 1]);
    if (gone >= progress.left) break;
  }
  final walking = Leg(
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
  return Journey(
    dep: j.dep,
    arr: j.arr,
    rides: j.rides,
    live: j.live,
    confidence: j.confidence,
    legs: [for (final (i, l) in j.legs.indexed) i == stage.leg ? walking : l],
    backup: j.backup,
    aboard: j.aboard,
    hurry: j.hurry,
  );
}
