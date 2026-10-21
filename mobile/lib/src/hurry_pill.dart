/// Hurrying asked for, in amber with a runner.
library;

import 'package:flutter/material.dart';

import 'explain.dart';

class HurryPill extends StatelessWidget {
  const HurryPill({
    super.key,
    required this.text,
    required this.hint,
    this.explains = true,
  });

  final String text;

  /// Said on a tap
  final String hint;

  /// Whether a tap says [hint]. Off on a card that is one tap target
  final bool explains;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Colors.amber, fontWeight: FontWeight.w600);
    final pill = Container(
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
          if (explains) ...[
            const SizedBox(width: 2),
            const Icon(
              Icons.info_outline,
              size: infoIconSize,
              color: Colors.amber,
            ),
          ],
        ],
      ),
    );
    if (!explains) return pill;
    return InkWell(
      onTap: () => explain(context, text, hint),
      borderRadius: BorderRadius.circular(12),
      child: pill,
    );
  }
}
