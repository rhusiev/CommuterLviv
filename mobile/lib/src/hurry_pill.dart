/// Hurrying asked for, in amber with a runner.
library;

import 'package:flutter/material.dart';

class HurryPill extends StatelessWidget {
  const HurryPill({super.key, required this.text, required this.hint});

  final String text;

  /// Said on a long press
  final String hint;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Colors.amber, fontWeight: FontWeight.w600);
    return Tooltip(
      message: hint,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_run, size: 14, color: Colors.amber),
            const SizedBox(width: 4),
            Text(text, style: style),
          ],
        ),
      ),
    );
  }
}
