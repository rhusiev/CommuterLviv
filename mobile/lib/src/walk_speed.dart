/// How fast you walk: a step at a time, per search and as the usual.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart' hide Theme;
import 'package:flutter/material.dart' as material show Theme;

import 'api.dart';
import 'models.dart';
import 'strings.dart';

class SpeedStepper extends StatelessWidget {
  const SpeedStepper({
    super.key,
    required this.kmh,
    required this.onChanged,
    this.max,
  });

  final double kmh;
  final ValueChanged<double> onChanged;

  /// The fastest it steps to, [walkKmh]'s by default.
  final double? max;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        onPressed: kmh <= walkKmh.min
            ? null
            : () => onChanged(kmh - walkKmh.step),
        icon: const Icon(Icons.remove),
        tooltip: txt.slower,
      ),
      SizedBox(
        width: 72,
        child: Text(
          txt.kmh(kmh),
          textAlign: TextAlign.center,
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ),
      IconButton(
        onPressed: kmh >= (max ?? walkKmh.max)
            ? null
            : () => onChanged(kmh + walkKmh.step),
        icon: const Icon(Icons.add),
        tooltip: txt.faster,
      ),
    ],
  );
}

/// The usual walking speed, and the hurrying one, kept the moment either is
/// stepped.
class WalkSpeedSheet extends StatefulWidget {
  const WalkSpeedSheet({super.key, required this.api});

  final Api api;

  @override
  State<WalkSpeedSheet> createState() => _WalkSpeedSheetState();
}

class _WalkSpeedSheetState extends State<WalkSpeedSheet> {
  late double _kmh = widget.api.walkSpeed;
  late double? _hurry = widget.api.hurrySpeed;

  void _keepHurry(double? kmh) {
    setState(() => _hurry = kmh);
    unawaited(widget.api.setHurrySpeed(kmh));
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            txt.walkSpeed,
            style: material.Theme.of(context).textTheme.titleMedium,
          ),
          SpeedStepper(
            kmh: _kmh,
            onChanged: (v) {
              setState(() => _kmh = v);
              unawaited(widget.api.setWalkSpeed(v));
            },
          ),
          Text(
            txt.walkSpeedHint,
            textAlign: TextAlign.center,
            style: material.Theme.of(context).textTheme.bodySmall,
          ),
          SwitchListTile(
            title: Text(txt.hurrySpeed),
            value: _hurry != null,
            onChanged: (on) => _keepHurry(on ? _kmh : null),
          ),
          if (_hurry case final hurry?)
            SpeedStepper(kmh: hurry, max: hurryKmh.max, onChanged: _keepHurry),
          Text(
            txt.hurrySpeedHint,
            textAlign: TextAlign.center,
            style: material.Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}
