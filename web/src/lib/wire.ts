/** Reader for the binary map frames. Mirrors `commuterlviv/live/wire.py` and the
 * constants below must stay identical to it: a frame carries no box of its own. */

export const VERSION = 1;
export const SNAPSHOT = 0;
export const DELTA = 1;

const LAT0 = 49.7;
const LON0 = 23.85;
const DLAT = 0.3;
const DLON = 0.45;
const SCALE = 65535;

const ROW = 10;
const HEADER = 10; // u8 kind, u8 version, u32 t, u16 n, u16 gone

export type Frame = {
  kind: number;
  t: number;
  n: number;
  ids: Uint16Array;
  routes: Uint16Array;
  lats: Float64Array;
  lons: Float64Array;
  headings: Float32Array;
  flags: Uint8Array;
  gone: Uint16Array;
};

export function decode(buf: ArrayBuffer): Frame {
  const v = new DataView(buf);
  const kind = v.getUint8(0);
  const version = v.getUint8(1);
  if (version !== VERSION) throw new Error(`frame version ${version}, expected ${VERSION}`);
  const t = v.getUint32(2, true);
  const n = v.getUint16(6, true);
  const m = v.getUint16(8, true);

  const ids = new Uint16Array(n);
  const routes = new Uint16Array(n);
  // Doubles, not floats: near 50 degrees a float32 steps by about 4e-6 and the
  // wire quantum is 4.6e-6, so a float32 loses most of the row's precision
  const lats = new Float64Array(n);
  const lons = new Float64Array(n);
  const headings = new Float32Array(n);
  const flags = new Uint8Array(n);

  for (let i = 0; i < n; i++) {
    const o = HEADER + i * ROW;
    ids[i] = v.getUint16(o, true);
    routes[i] = v.getUint16(o + 2, true);
    lons[i] = LON0 + (v.getUint16(o + 4, true) / SCALE) * DLON;
    lats[i] = LAT0 + (v.getUint16(o + 6, true) / SCALE) * DLAT;
    headings[i] = (v.getUint8(o + 8) * 360) / 256;
    flags[i] = v.getUint8(o + 9);
  }

  const gone = new Uint16Array(m);
  const go = HEADER + n * ROW;
  for (let i = 0; i < m; i++) gone[i] = v.getUint16(go + i * 2, true);

  return { kind, t, n, ids, routes, lats, lons, headings, flags, gone };
}

/** Bit 0: the last real fix is older than the model's freshness window, so this
 * position is extrapolated rather than reported. */
export const STALE_FLAG = 1;

/** Bit 1: the vehicle is under way. Without it the heading is still the route's
 * direction there, but says where the vehicle will go, not where it is going. */
export const MOVING_FLAG = 2;
