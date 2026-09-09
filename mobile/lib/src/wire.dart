/// The reader for the binary map frames. A port of `commuterlviv/live/wire.py`, and
/// the constants must stay identical to it: a frame carries no box of its own.
///
/// Ten bytes per vehicle, read straight out of the [ByteData] into flat typed
/// lists. Nothing here allocates per vehicle - four hundred small objects per
/// frame is the one thing that would show up in a frame budget.
library;

import 'dart:typed_data';

const version = 1;
const snapshot = 0;
const delta = 1;

const _lat0 = 49.7;
const _lon0 = 23.85;
const _dLat = 0.3;
const _dLon = 0.45;
const _scale = 65535.0;

const _row = 10;
const _header = 10; // u8 kind, u8 version, u32 t, u16 n, u16 gone

/// Bit 0: the last real fix is older than the model's freshness window, so this
/// position is extrapolated rather than reported.
const staleFlag = 1;

/// Bit 1: the tracker's speed clears "stopped" by more than its own error, so
/// the vehicle is under way and its direction is worth drawing.
const movingFlag = 2;

class Frame {
  Frame({
    required this.kind,
    required this.t,
    required this.ids,
    required this.routes,
    required this.lats,
    required this.lons,
    required this.headings,
    required this.flags,
    required this.gone,
  });

  final int kind;
  final int t;
  final Uint16List ids;
  final Uint16List routes;

  /// Doubles, not floats: near 50 degrees a float32 steps by about 4e-6 and the
  /// wire quantum is 4.6e-6, so a float32 would throw away most of the precision
  /// the ten-byte row was paying for.
  final Float64List lats;
  final Float64List lons;
  final Float64List headings;
  final Uint8List flags;
  final Uint16List gone;

  int get n => ids.length;
}

Frame decode(Uint8List buf) {
  final v = ByteData.sublistView(buf);
  final kind = v.getUint8(0);
  final got = v.getUint8(1);
  if (got != version) {
    throw FormatException('frame version $got, expected $version');
  }
  final t = v.getUint32(2, Endian.little);
  final n = v.getUint16(6, Endian.little);
  final m = v.getUint16(8, Endian.little);

  final ids = Uint16List(n);
  final routes = Uint16List(n);
  final lats = Float64List(n);
  final lons = Float64List(n);
  final headings = Float64List(n);
  final flags = Uint8List(n);

  for (var i = 0; i < n; i++) {
    final o = _header + i * _row;
    ids[i] = v.getUint16(o, Endian.little);
    routes[i] = v.getUint16(o + 2, Endian.little);
    lons[i] = _lon0 + v.getUint16(o + 4, Endian.little) / _scale * _dLon;
    lats[i] = _lat0 + v.getUint16(o + 6, Endian.little) / _scale * _dLat;
    headings[i] = v.getUint8(o + 8) * 360 / 256;
    flags[i] = v.getUint8(o + 9);
  }

  final gone = Uint16List(m);
  final go = _header + n * _row;
  for (var i = 0; i < m; i++) {
    gone[i] = v.getUint16(go + i * 2, Endian.little);
  }

  return Frame(
    kind: kind,
    t: t,
    ids: ids,
    routes: routes,
    lats: lats,
    lons: lons,
    headings: headings,
    flags: flags,
    gone: gone,
  );
}
