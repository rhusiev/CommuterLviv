import { describe, expect, test } from "vitest";
import { current, riddenBy, rows, underWay, WAIT_MIN_S } from "./legs";
import type { Progress } from "./follow";
import type { Journey, Leg } from "./types";

const T0 = 1_790_000_000;
const MIN_S = 60;

const walk = (dep: number, arr: number, a: number, b: number): Leg => ({ kind: "walk", dep, arr, a, b });
const ride = (dep: number, arr: number, a: number, b: number, route = 7): Leg => ({
  kind: "ride",
  dep,
  arr,
  a,
  b,
  route,
});

/** Door to stop 1, route 7 to stop 2, change on foot to stop 3, route 9 to
 *  stop 4, walk to the door - `waits` seconds at stop 1 and `change` at 3 */
const journey = (waits: number, change: number): Journey => {
  const r1 = T0 + 5 * MIN_S + waits;
  const w2 = r1 + 10 * MIN_S;
  const r2 = w2 + 2 * MIN_S + change;
  return {
    dep: T0,
    arr: r2 + 15 * MIN_S,
    rides: 2,
    live: true,
    confidence: "live",
    backup: 0,
    legs: [
      walk(T0, T0 + 5 * MIN_S, -1, 1),
      ride(r1, w2, 1, 2),
      walk(w2, w2 + 2 * MIN_S, 2, 3),
      ride(r2, r2 + 10 * MIN_S, 3, 4, 9),
      walk(r2 + 10 * MIN_S, r2 + 15 * MIN_S, 4, -1),
    ],
  };
};

describe("rows", () => {
  test("lists each leg with a wait before a ride a minute or more later", () => {
    const j = journey(3 * MIN_S, WAIT_MIN_S);

    const got = rows(j);

    expect(got.map((r) => [r.kind, r.leg])).toEqual([
      ["walk", 0],
      ["wait", 1],
      ["ride", 1],
      ["walk", 2],
      ["wait", 3],
      ["ride", 3],
      ["walk", 4],
    ]);
    expect(got[1]).toMatchObject({ dep: j.legs[0]!.arr, arr: j.legs[1]!.dep, at: 1 });
    expect(got[5]).toMatchObject({ route: 9, a: 3, b: 4 });
  });

  test("a gap under a minute gets no wait", () => {
    const got = rows(journey(WAIT_MIN_S - 1, 0));
    expect(got.some((r) => r.kind === "wait")).toBe(false);
  });

  test("only the walk between two rides is a change", () => {
    const got = rows(journey(0, 0)).filter((r) => r.kind === "walk");
    expect(got.map((r) => [r.to, r.change])).toEqual([
      [1, false],
      [3, true],
      [-1, false],
    ]);
  });

  test("a journey begun on board has no wait before its first ride", () => {
    const j = journey(0, 0);
    const got = rows({ ...j, aboard: true, legs: j.legs.slice(1) });
    expect(got[0]).toMatchObject({ kind: "ride", leg: 0 });
  });
});

describe("current", () => {
  const list = rows(journey(3 * MIN_S, 0));

  test("waiting is on the wait, riding on the ride", () => {
    expect(list[current(list, { kind: "wait", leg: 1 })]!.kind).toBe("wait");
    expect(list[current(list, { kind: "ride", leg: 1, veh: null })]!.kind).toBe("ride");
  });

  test("waiting for a ride with no wait listed is on the ride", () => {
    expect(list[current(list, { kind: "wait", leg: 3 })]).toMatchObject({ kind: "ride", leg: 3 });
  });

  test("arrived is on no row", () => {
    expect(current(list, { kind: "arrived" })).toBe(-1);
  });
});

describe("riddenBy", () => {
  test("is the vehicles the rides are planned on, and none for a ride on the timetable alone", () => {
    const j = journey(0, 0);
    j.legs[1] = { ...j.legs[1]!, veh: 412 };
    j.legs[3] = { ...j.legs[3]!, veh: null };

    expect([...riddenBy(j)]).toEqual([412]);
  });

  test("is no vehicle while no journey is drawn", () => {
    expect(riddenBy(null).size).toBe(0);
  });
});

describe("underWay", () => {
  /** A walk north along a meridian, a point every ~111 m */
  const STEP = 0.001;
  const walking = (): Journey => {
    const j = journey(0, 0);
    const pts: [number, number][] = [0, 1, 2, 3, 4].map((i) => [49.8 + i * STEP, 24.0]);
    j.legs[0] = { ...j.legs[0]!, pts };
    return j;
  };
  const progress = (stage: Progress["stage"], left: number, astray = false): Progress => ({
    stage,
    left,
    astray,
    passed: false,
    soon: false,
  });
  const HERE = { lat: 49.8015, lon: 24.0002, t: T0 + MIN_S };

  test("draws the walk under way from where I am, along what is left of its line", () => {
    const j = underWay(walking(), progress({ kind: "walk", leg: 0 }, 250), HERE);
    const pts = j.legs[0]!.pts!;

    expect(pts[0]).toEqual([HERE.lat, HERE.lon]);
    expect(pts.slice(1)).toEqual([2, 3, 4].map((i) => [49.8 + i * STEP, 24.0]));
    expect(j.legs[0]!.dep).toBe(HERE.t);
  });

  test("leaves a walk strayed from as planned", () => {
    const plan = walking();

    expect(underWay(plan, progress({ kind: "walk", leg: 0 }, 250, true), HERE).legs).toEqual(plan.legs);
  });

  test("leaves the legs already done off, once waiting or aboard", () => {
    const plan = walking();

    expect(underWay(plan, progress({ kind: "wait", leg: 1 }, 0), HERE).legs).toEqual(plan.legs.slice(1));
    expect(underWay(plan, progress({ kind: "ride", leg: 1, veh: 7 }, 0), HERE).legs).toEqual(plan.legs.slice(1));
  });

  test("leaves an arrived journey whole", () => {
    const plan = walking();

    expect(underWay(plan, progress({ kind: "arrived" }, 0), HERE)).toBe(plan);
  });
});

