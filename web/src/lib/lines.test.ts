import { describe, expect, test } from "vitest";
import { directions, HOW_OFTEN_AROUND_S, lineHours, lineRows, opened, RECENT_LINES, routesNear } from "./lines";
import type { Catalog } from "./types";

describe("directions", () => {
  test("lists each way once, by the shape calling at the most stops", () => {
    const shape = {
      lines: [
        { dir: 1, pts: [], stops: [3, 2, 1, 0] },
        { dir: 0, pts: [], stops: [0, 1] },
        { dir: 0, pts: [], stops: [0, 1, 2, 3] },
      ],
    };

    expect(directions(shape)).toEqual([
      { dir: 0, stops: [0, 1, 2, 3] },
      { dir: 1, stops: [3, 2, 1, 0] },
    ]);
  });

  test("has nothing to list from a service that sends no stops", () => {
    expect(directions({ lines: [{ dir: 0, pts: [] }] })).toEqual([]);
    expect(directions(undefined)).toEqual([]);
  });
});

describe("lineRows", () => {
  test("gives each stop this route's next arrival, not another route's", () => {
    const rows = lineRows(
      [5, 6],
      { "5": [{ route: 9, veh: 1, t: 50 }, { route: 2, veh: 3, t: 80 }] },
      2,
    );

    expect(rows.map((r) => r.next?.t ?? null)).toEqual([80, null]);
  });

  test("puts a vehicle at the stop it reaches soonest", () => {
    const rows = lineRows(
      [0, 1, 2],
      {
        "0": [{ route: 2, veh: 7, t: 300 }],
        "1": [{ route: 2, veh: 4, t: 100 }],
        "2": [
          { route: 2, veh: 4, t: 200 },
          { route: 2, veh: 7, t: 400 },
        ],
      },
      2,
    );

    expect(rows.map((r) => r.vehs)).toEqual([[7], [4], []]);
  });

  test("leaves a vehicle finishing its previous trip off the line", () => {
    const rows = lineRows([0], { "0": [{ route: 2, veh: 7, t: 300, planned: true }] }, 2);

    expect(rows[0]!.vehs).toEqual([]);
    expect(rows[0]!.next?.veh).toBe(7);
  });
});

test("routesNear takes the routes of the stops within the radius only", () => {
  const cat: Catalog = {
    routes: [],
    stops: [
      { id: "a", name: "A", code: "", lat: 49.84, lon: 24.03, routes: [0, 1] },
      { id: "b", name: "B", code: "", lat: 49.85, lon: 24.03, routes: [2] },
    ],
  };

  expect([...routesNear(cat, { lat: 49.8405, lon: 24.03 }, 500)].sort()).toEqual([0, 1]);
});

describe("opened", () => {
  test("puts the line opened first, once", () => {
    expect(opened(["a", "b", "c"], "b")).toEqual(["b", "a", "c"]);
  });

  test("keeps only the latest few", () => {
    const many = Array.from({ length: RECENT_LINES }, (_, i) => `r${i}`);

    expect(opened(many, "new")).toEqual(["new", ...many.slice(0, RECENT_LINES - 1)]);
  });
});

describe("lineHours", () => {
  const MIN = 60;
  const dep = [0, 8, 16, 24, 32, 60, 120].map((m) => 1_000_000 + m * MIN);

  test("gives the day's first and last departure and the typical gap around now", () => {
    expect(lineHours(dep, dep[2]!)).toEqual({ first: dep[0], last: dep[6], every: 8 * MIN });
  });

  test("says no gap where too few leave around now", () => {
    expect(lineHours(dep, dep[6]! + HOW_OFTEN_AROUND_S)?.every).toBeNull();
  });

  test("says nothing of a day without departures", () => {
    expect(lineHours([], 0)).toBeNull();
  });
});
