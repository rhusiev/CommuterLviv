import { describe, expect, test, vi } from "vitest";
import { clock } from "./eta";
import { journeyTags, SHORT_WALK_S } from "./tags";
import type { Leg } from "./types";

// `clock` lives beside the strings, which read `localStorage` as they load
vi.hoisted(() => vi.stubGlobal("localStorage", { getItem: () => null }));

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
});
