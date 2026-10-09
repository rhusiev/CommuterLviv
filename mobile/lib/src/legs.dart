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
    final before = i > 0 ? j.legs[i - 1].arr : null;
    if (before != null && leg.dep - before >= waitMinS) {
      out.add(
        PlanRow(
          PlanRowKind.wait,
          i,
          dep: before,
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
