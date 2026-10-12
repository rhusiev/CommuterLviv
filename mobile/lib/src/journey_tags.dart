/// The times pinned to the map along the picked journey: one pill per stop.
library;

import 'package:latlong2/latlong.dart';

import 'eta.dart';
import 'models.dart';

/// Times within this far of each other share a pill: one stop at every zoom
const sameStopM = 25.0;

/// A shorter walk gets no times of its own: somebody standing at the stop
/// would read it as a walk from a minute to the same minute
const shortWalkS = 60;

/// One pill: where it wants to sit and what it says.
class JourneyTag {
  const JourneyTag(this.point, this.text);

  final LatLng point;
  final String text;
}

/// Timestamps only, one pill per stop; durations stay in the planner's list.
/// A third and further time on one spot gets a pill of its own there. [legs]
/// are the ones drawn, each with a path.
List<JourneyTag> journeyTags(List<Leg> legs) {
  final groups = <_Group>[];
  for (final leg in legs) {
    if (leg.walking && leg.arr - leg.dep < shortWalkS) continue;
    _at(groups, leg.pts.first).on.add(leg.dep);
    _at(groups, leg.pts.last).off.add(leg.arr);
  }
  return [
    for (final g in groups) ...[
      JourneyTag(g.point, g.text),
      for (final extra in g.extras) JourneyTag(g.point, clockTime(extra)),
    ],
  ];
}

/// One stop's worth of times: every alighting and boarding within
/// [sameStopM]. [text] reads off → on for a change, or one time when there is
/// only it or both are the same minute; [extras] holds a third and further
/// time, which the stack draws as its own pill on the same spot.
class _Group {
  _Group(this.point);

  final LatLng point;
  final List<int> off = [];
  final List<int> on = [];

  String get text {
    final last = off.isNotEmpty ? clockTime(off.last) : null;
    final first = on.isNotEmpty ? clockTime(on.first) : null;
    if (last != null && first != null && last != first) {
      return '$last → $first';
    }
    return (last ?? first)!;
  }

  Iterable<int> get extras sync* {
    for (var i = 0; i + 1 < off.length; i++) {
      yield off[i];
    }
    for (var i = 1; i < on.length; i++) {
      yield on[i];
    }
  }
}

/// The group [at] belongs to, opening one when it stands alone.
_Group _at(List<_Group> groups, LatLng at) {
  const near = Distance();
  for (final g in groups) {
    if (near(g.point, at) < sameStopM) return g;
  }
  final opened = _Group(at);
  groups.add(opened);
  return opened;
}
