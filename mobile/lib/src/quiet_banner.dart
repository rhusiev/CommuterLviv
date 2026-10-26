import 'package:flutter/material.dart';

import 'live.dart';
import 'strings.dart';
import 'theme.dart';

/// The web's amber-200, amber-400 and slate-300, so a warning reads the same
/// in both.
const _title = Color(0xfffde68a);
const _mark = Color(0xfffbbf24);
const _detail = Color(0xffcbd5e1);

/// As wide as the web's banner (`max-w-md`), so a tablet does not stretch it
const _maxWidth = 448.0;
const _markSize = 20.0;

/// Says while [Live.quiet] holds that there may be an air raid alert, and under
/// that why positions and arrival times may be missing or off. Closed, it stays
/// closed until the vehicles go quiet again.
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
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Semantics(
            liveRegion: true,
            child: Floating(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(controlRadius),
                side: const BorderSide(color: hair),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: CustomPaint(
                        size: Size.square(_markSize),
                        painter: _Siren(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              txt.quietTitle,
                              style: const TextStyle(
                                color: _title,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              txt.quietDetail,
                              style: const TextStyle(
                                color: _detail,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, color: _mark, size: 20),
                      onPressed: () => setState(() => _shut = true),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// The web's `siren` glyph (`web/src/components/Icon.tsx`), drawn on the same
/// 24-unit grid: a lamp on a base, with rays.
class _Siren extends CustomPainter {
  const _Siren();

  static const _grid = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _grid);
    final pen = Paint()
      ..color = _mark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final lamp = Path()
      ..moveTo(7, 17)
      ..lineTo(7, 12)
      ..arcToPoint(const Offset(17, 12), radius: const Radius.circular(5))
      ..lineTo(17, 17)
      ..addRect(const Rect.fromLTRB(4.5, 17, 19.5, 20.5));
    canvas.drawPath(lamp, pen);
    for (final (a, b) in const [
      (Offset(12, 2), Offset(12, 4)),
      (Offset(4.5, 5.5), Offset(6, 7)),
      (Offset(19.5, 5.5), Offset(18, 7)),
      (Offset(12, 10), Offset(12, 13)),
    ]) {
      canvas.drawLine(a, b, pen);
    }
  }

  @override
  bool shouldRepaint(_Siren old) => false;
}
