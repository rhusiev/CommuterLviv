/// How fast the streets are running, for as long as the view is open. The
/// stretches themselves never change, so they are fetched once and kept across
/// openings; the numbers are small, and are asked for again every minute while
/// the view is up and not at all while it is down.
library;

import 'dart:async';

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter_map/flutter_map.dart';

import 'api.dart';
import 'models.dart';

const trafficPeriod = Duration(seconds: 60);

/// The ramp: actual over timetabled travel time, and the colour for it. 1 is
/// exactly the timetable, so green is ahead of it and red is a crawl.
const trafficRamp = <(double, Color)>[
  (0.85, Color(0xff22c55e)),
  (1.0, Color(0xffa3e635)),
  (1.15, Color(0xfffacc15)),
  (1.3, Color(0xfffb923c)),
  (1.6, Color(0xffef4444)),
];

/// Null where too little has been seen to say, which is drawn as nothing.
Color? trafficColour(double? ratio) {
  if (ratio == null) return null;
  var (was, colour) = trafficRamp.first;
  if (ratio <= was) return colour;
  for (final (upto, next) in trafficRamp.skip(1)) {
    if (ratio <= upto) {
      return Color.lerp(colour, next, (ratio - was) / (upto - was));
    }
    was = upto;
    colour = next;
  }
  return colour;
}

/// Held across openings of the view, and across a rebuild of the layer. The
/// server it came from is kept with it: another one measures other stretches.
({String base, Streets lines})? _held;

class TrafficLayer extends StatefulWidget {
  const TrafficLayer({super.key, required this.api});

  final Api api;

  @override
  State<TrafficLayer> createState() => _TrafficLayerState();
}

class _TrafficLayerState extends State<TrafficLayer> {
  /// Built when a reading arrives rather than in `build`, which the map calls on
  /// every pan and frame: there are tens of thousands of stretches
  List<Polyline>? _drawn;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(trafficPeriod, (_) => unawaited(_load()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (_held?.base != widget.api.base) {
        _held = (base: widget.api.base, lines: await widget.api.streets());
      }
    } on Exception {
      // Nothing to colour, so the view is simply the map it sits on
      return;
    }
    await _ask();
  }

  Future<void> _ask() async {
    try {
      final got = await widget.api.traffic();
      final streets = _held!.lines.lines;
      final drawn = [
        for (var i = 0; i < streets.length && i < got.ratio.length; i++)
          if (trafficColour(got.ratio[i]) case final colour?)
            Polyline(
              points: streets[i],
              color: colour.withValues(alpha: 0.85),
              strokeWidth: 4,
            ),
      ];
      if (mounted) setState(() => _drawn = drawn);
    } on Exception {
      // The last numbers stay up rather than the view emptying for a minute
    }
  }

  @override
  Widget build(BuildContext context) {
    final drawn = _drawn;
    if (drawn == null) return const SizedBox.shrink();
    return PolylineLayer(polylines: drawn);
  }
}
