/** The decoder against bytes the server actually produced.
 *
 * The frame below was encoded by `commuterlviv.live.wire.encode` and pasted
 * here, so this is a test of agreement between two languages rather than of the
 * TypeScript against itself. `mobile/test/wire_test.dart` says how to
 * regenerate it. */

import { describe, expect, test } from "vitest";
import { DELTA, MOVING_FLAG, STALE_FLAG, decode } from "./wire";

/** Three vehicles - centre, south-west corner, far corner - and two gone ids */
const FRAME = new Uint8Array([
  1, 1, 210, 4, 0, 0, 3, 0, 2, 0,
  7, 0, 0, 0, 58, 102, 53, 119, 0, 0,
  255, 255, 41, 0, 0, 0, 0, 0, 128, 1,
  1, 0, 3, 0, 240, 255, 233, 255, 255, 3,
  9, 0, 12, 0,
]);

/** Half a metre is the quantum, so equality is to seven decimal places */
const TOLERANCE = 1e-7;

const expectNear = (actual: number | undefined, expected: number) =>
  expect(Math.abs(actual! - expected)).toBeLessThanOrEqual(TOLERANCE);

describe("wire", () => {
  test("a delta decodes to what the server encoded", () => {
    const f = decode(FRAME.slice().buffer);

    expect(f.kind).toBe(DELTA);
    expect(f.t).toBe(1234);
    expect(f.n).toBe(3);
    expect([...f.ids]).toEqual([7, 65535, 1]);
    expect([...f.routes]).toEqual([0, 41, 3]);
    expect([...f.gone]).toEqual([9, 12]);

    expectNear(f.lats[0], 49.83969787);
    expectNear(f.lons[0], 24.02969787);
    expectNear(f.lats[1], 49.7);
    expectNear(f.lons[1], 23.85);
    expectNear(f.lats[2], 49.99989929);
    expectNear(f.lons[2], 24.299897);

    // One byte of heading is 1.40625 degrees, and 359.5 lands on 358.59375
    expect([...f.headings]).toEqual([0.0, 180.0, 358.59375]);
  });

  test("the flag bits say stale and moving", () => {
    const f = decode(FRAME.slice().buffer);

    expect(f.flags[0]! & STALE_FLAG).toBe(0);
    expect(f.flags[0]! & MOVING_FLAG).toBe(0);
    expect(f.flags[1]! & STALE_FLAG).toBe(STALE_FLAG);
    expect(f.flags[1]! & MOVING_FLAG).toBe(0);
    expect(f.flags[2]! & STALE_FLAG).toBe(STALE_FLAG);
    expect(f.flags[2]! & MOVING_FLAG).toBe(MOVING_FLAG);
  });

  test("a frame from a newer server is refused, not misread", () => {
    const wrong = FRAME.slice();
    wrong[1] = 2;
    expect(() => decode(wrong.buffer)).toThrow();
  });
});
