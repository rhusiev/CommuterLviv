import 'package:flutter/material.dart';

import 'live.dart';
import 'strings.dart';
import 'theme.dart';

/// The web's amber-200 and amber-400, so a warning reads the same in both.
const _text = Color(0xfffde68a);
const _close = Color(0xfffbbf24);

/// Says while [Live.quiet] holds that positions and arrival times may be
/// missing or off. Closed, it stays closed until the vehicles go quiet again.
class QuietBanner extends StatefulWidget {
  const QuietBanner({super.key, required this.live});

  final Live live;

  @override
  State<QuietBanner> createState() => _QuietBannerState();
}

class _QuietBannerState extends State<QuietBanner> {
  bool _shut = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.live,
    builder: (context, _) {
      if (!widget.live.quiet) _shut = false;
      if (!widget.live.quiet || _shut) return const SizedBox.shrink();
      return Floating(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          side: const BorderSide(color: hair),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(txt.quiet, style: const TextStyle(color: _text)),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: const Icon(Icons.close, color: _close),
                onPressed: () => setState(() => _shut = true),
              ),
            ],
          ),
        ),
      );
    },
  );
}
