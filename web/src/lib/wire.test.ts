/** The decoder against bytes the server actually produced.
 *
 * `tests/wire_frame.json` holds a frame `commuterlviv.live.wire.encode` writes,
 * which `tests/wire_test.py` checks, so this is a test of agreement between the
 * languages rather than of the TypeScript against itself. */

import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import { MOVING_FLAG, STALE_FLAG, decode } from "./wire";

type Shared = {
  kind: number;
  t: number;
  gone: number[];
  vehicles: { id: number; route: number; stale: boolean; moving: boolean }[];
  decoded: { lat: number; lon: number; heading: number }[];
  bytes: number[];
};

const SHARED: Shared = JSON.parse(
  readFileSync(new URL("../../../tests/wire_frame.json", import.meta.url), "utf8"),
);

/** Half a metre is the quantum, so equality is to seven decimal places */
const TOLERANCE = 1e-7;

const frame = () => new Uint8Array(SHARED.bytes).buffer;

describe("wire", () => {
  test("a delta decodes to what the server encoded", () => {
    const f = decode(frame());

    expect(f.kind).toBe(SHARED.kind);
    expect(f.t).toBe(SHARED.t);
    expect(f.n).toBe(SHARED.vehicles.length);
    expect([...f.ids]).toEqual(SHARED.vehicles.map((v) => v.id));
    expect([...f.routes]).toEqual(SHARED.vehicles.map((v) => v.route));
    expect([...f.gone]).toEqual(SHARED.gone);
    SHARED.decoded.forEach((d, i) => {
      expect(Math.abs(f.lats[i]! - d.lat)).toBeLessThanOrEqual(TOLERANCE);
      expect(Math.abs(f.lons[i]! - d.lon)).toBeLessThanOrEqual(TOLERANCE);
    });
    expect([...f.headings]).toEqual(SHARED.decoded.map((d) => d.heading));
  });

  test("the flag bits say stale and moving", () => {
    const f = decode(frame());

    SHARED.vehicles.forEach((v, i) => {
      expect((f.flags[i]! & STALE_FLAG) !== 0).toBe(v.stale);
      expect((f.flags[i]! & MOVING_FLAG) !== 0).toBe(v.moving);
    });
  });

  test("a frame from a newer server is refused, not misread", () => {
    const wrong = new Uint8Array(SHARED.bytes);
    wrong[1] = 2;
    expect(() => decode(wrong.buffer)).toThrow();
  });
});
