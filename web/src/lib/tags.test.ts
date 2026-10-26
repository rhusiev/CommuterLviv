import { describe, expect, test } from "vitest";
import { clock } from "./eta";
import { journeyTags, onPlace, SHORT_WALK_S } from "./tags";
import type { Leg } from "./types";

// on a minute, so a few seconds later is still the same one on the clock
const T0 = 1_790_000_040;
const MIN_S = 60;
const DOOR: [number, number] = [49.84, 24.0];
const STOP: [number, number] = [49.841, 24.0];
const OTHER: [number, number] = [49.85, 24.0];

const walk = (dep: number, arr: number, from = DOOR, to = STOP): Leg => ({
  kind: "walk",
  dep,
  arr,
  a: -1,
  b: 1,
  pts: [from, to],
});
const ride = (dep: number, arr: number, from = STOP, to = OTHER): Leg => ({
  kind: "ride",
  dep,
  arr,
  a: 1,
  b: 2,
  route: 7,
  pts: [from, to],
});
const texts = (legs: Leg[]) => journeyTags(legs).map((tag) => tag.text);

describe("journeyTags", () => {
  test("somebody already at the stop is shown only when the ride leaves", () => {
    const legs = [walk(T0, T0 + 5, STOP, STOP), ride(T0 + 34, T0 + 10 * MIN_S)];

    expect(texts(legs)).toEqual([clock(T0 + 34), clock(T0 + 10 * MIN_S)]);
  });

  test("a walk to the stop of a minute or more has its own times", () => {
    const legs = [walk(T0, T0 + SHORT_WALK_S), ride(T0 + 2 * MIN_S, T0 + 10 * MIN_S)];

    expect(texts(legs)).toEqual([
      clock(T0),
      `${clock(T0 + SHORT_WALK_S)} → ${clock(T0 + 2 * MIN_S)}`,
      clock(T0 + 10 * MIN_S),
    ]);
  });

  test("getting off and on again within a minute reads as one time", () => {
    const legs = [ride(T0, T0 + 5, OTHER, STOP), ride(T0 + 30, T0 + 10 * MIN_S, STOP, OTHER)];

    expect(texts(legs)[1]).toBe(clock(T0 + 30));
  });

  test("a short walk between two stops leaves each its own ride's time", () => {
    const near: [number, number] = [STOP[0], STOP[1] + 0.001];
    const legs = [
      ride(T0, T0 + 5 * MIN_S, OTHER, STOP),
      walk(T0 + 5 * MIN_S, T0 + 5 * MIN_S + 40, STOP, near),
      ride(T0 + 8 * MIN_S, T0 + 20 * MIN_S, near, DOOR),
    ];

    expect(texts(legs)).toEqual([
      clock(T0),
      clock(T0 + 5 * MIN_S),
      clock(T0 + 8 * MIN_S),
      clock(T0 + 20 * MIN_S),
    ]);
  });

  test("two stops 25 m apart or more keep a pill each, whichever way they lie", () => {
    // 20 m north and 20 m east: each closer than 25 m, the two together 28 m
    const corner: [number, number] = [STOP[0] + 0.00018, STOP[1] + 0.00028];
    const legs = [
      ride(T0, T0 + 5 * MIN_S, OTHER, STOP),
      ride(T0 + 5 * MIN_S + 30, T0 + 20 * MIN_S, corner, DOOR),
    ];

    expect(texts(legs)).toEqual([
      clock(T0),
      clock(T0 + 5 * MIN_S),
      clock(T0 + 5 * MIN_S + 30),
      clock(T0 + 20 * MIN_S),
    ]);
  });
});

describe("onPlace", () => {
  // 20 m north of the stop, and 30 m
  const HOME = { lat: STOP[0] + 0.00018, lon: STOP[1] };
  const AWAY = { lat: STOP[0] + 0.00027, lon: STOP[1] };
  const at = { lat: STOP[0], lon: STOP[1] };

  test("a pill within 25 m of a saved place stands on it", () => {
    expect(onPlace(at, [AWAY, HOME])).toBe(true);
  });

  test("a pill further from every saved place stands on none", () => {
    expect(onPlace(at, [AWAY])).toBe(false);
    expect(onPlace(at, [])).toBe(false);
  });
});
