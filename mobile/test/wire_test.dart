/// The decoder against bytes the server actually produced.
///
/// `tests/wire_frame.json` holds a frame `commuterlviv.live.wire.encode`
/// writes, which `tests/wire_test.py` checks, so this is a test of agreement
/// between the languages rather than of the Dart against itself.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:commuterlviv/src/wire.dart' as wire;

/// `flutter test` runs in the package, beside the repo's `tests/`.
final _shared = jsonDecode(
  File('../tests/wire_frame.json').readAsStringSync(),
) as Map<String, dynamic>;
final _vehicles = (_shared['vehicles'] as List).cast<Map<String, dynamic>>();
final _decoded = (_shared['decoded'] as List).cast<Map<String, dynamic>>();

Uint8List _frame() => Uint8List.fromList((_shared['bytes'] as List).cast());

/// Half a metre is the quantum, so equality is to seven decimal places.
const _tolerance = 1e-7;

void main() {
  test('a delta decodes to what the server encoded', () {
    final f = wire.decode(_frame());

    expect(f.kind, _shared['kind']);
    expect(f.t, _shared['t']);
    expect(f.n, _vehicles.length);
    expect(f.ids, [for (final v in _vehicles) v['id']]);
    expect(f.routes, [for (final v in _vehicles) v['route']]);
    expect(f.gone, _shared['gone']);
    for (final (i, d) in _decoded.indexed) {
      expect(f.lats[i], closeTo(d['lat'] as num, _tolerance));
      expect(f.lons[i], closeTo(d['lon'] as num, _tolerance));
    }
    expect(f.headings, [for (final d in _decoded) d['heading']]);
  });

  test('the flag bits say stale and moving', () {
    final f = wire.decode(_frame());

    for (final (i, v) in _vehicles.indexed) {
      expect(f.flags[i] & wire.staleFlag != 0, v['stale']);
      expect(f.flags[i] & wire.movingFlag != 0, v['moving']);
    }
  });

  test('a frame from a newer server is refused, not misread', () {
    final wrong = _frame()..[1] = 2;
    expect(() => wire.decode(wrong), throwsFormatException);
  });
}
