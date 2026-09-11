/// The decoder against bytes the server actually produced.
///
/// The frame below was encoded by `commuterlviv.live.wire.encode` and pasted here,
/// so this is a test of agreement between two languages rather than of the Dart
/// against itself. Regenerate it with:
///
///   .venv/bin/python -c "import numpy as np, commuterlviv.live.wire as w, \
///     commuterlviv.live.state as st; veh = np.zeros(3, st.VEH); …; \
///     print(list(w.encode(veh, 1234, w.DELTA, gone=[9, 12])))"
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:commuterlviv/src/wire.dart' as wire;

/// Three vehicles - centre, south-west corner, far corner - and two gone ids.
final _frame = Uint8List.fromList([
  1, 1, 210, 4, 0, 0, 3, 0, 2, 0, //
  7, 0, 0, 0, 58, 102, 53, 119, 0, 0, //
  255, 255, 41, 0, 0, 0, 0, 0, 128, 1, //
  1, 0, 3, 0, 240, 255, 233, 255, 255, 3, //
  9, 0, 12, 0,
]);

void main() {
  test('a delta decodes to what the server encoded', () {
    final f = wire.decode(_frame);

    expect(f.kind, wire.delta);
    expect(f.t, 1234);
    expect(f.n, 3);
    expect(f.ids, [7, 65535, 1]);
    expect(f.routes, [0, 41, 3]);
    expect(f.gone, [9, 12]);

    // Half a metre is the quantum, so equality is to seven decimal places
    expect(f.lats[0], closeTo(49.83969787, 1e-7));
    expect(f.lons[0], closeTo(24.02969787, 1e-7));
    expect(f.lats[1], closeTo(49.70, 1e-7));
    expect(f.lons[1], closeTo(23.85, 1e-7));
    expect(f.lats[2], closeTo(49.99989929, 1e-7));
    expect(f.lons[2], closeTo(24.29989700, 1e-7));

    // One byte of heading is 1.40625 degrees, and 359.5 lands on 358.59375
    expect(f.headings, [0.0, 180.0, 358.59375]);
  });

  test('the flag bits say stale and moving', () {
    final f = wire.decode(_frame);

    expect(f.flags[0] & wire.staleFlag, 0);
    expect(f.flags[0] & wire.movingFlag, 0);
    expect(f.flags[1] & wire.staleFlag, wire.staleFlag);
    expect(f.flags[1] & wire.movingFlag, 0);
    expect(f.flags[2] & wire.staleFlag, wire.staleFlag);
    expect(f.flags[2] & wire.movingFlag, wire.movingFlag);
  });

  test('a frame from a newer server is refused, not misread', () {
    final wrong = Uint8List.fromList(_frame)..[1] = 2;
    expect(() => wire.decode(wrong), throwsFormatException);
  });
}
