import { describe, expect, test } from "vitest";
import { ALL_STOPS_ZOOM, pickable, STOPS_ZOOM } from "./geo";
import type { Catalog, Journey, Leg } from "./types";
import { journeyBounds, splitStops } from "./useMapLayers";

const stop = (id: string, routes: number[]) => ({
  id,
  name: id,
  code: "",
  lat: 0,
  lon: 0,
  routes,
});
const CATALOG: Catalog = {
  routes: [],
  stops: [stop("s0", [0]), stop("s1", [1]), stop("s2", [0, 1])],
};

describe("the stops on the map", () => {
  test("a stop no route on the map calls at is faint, not left out", () => {
    expect(splitStops(CATALOG, [1])).toEqual({ stops: [1, 2], faint: [0] });
  });

  test("every stop can be clicked from close in, a watched one from further out", () => {
    const watched = [3];
    const faint = [7];

    expect(pickable(STOPS_ZOOM, watched, faint)).toEqual(watched);
    expect(pickable(ALL_STOPS_ZOOM - 0.1, watched, faint)).toEqual(watched);
    expect(pickable(ALL_STOPS_ZOOM, watched, faint)).toEqual([3, 7]);
  });
});

describe("the camera on a journey", () => {
  const at = (lat: number, lon: number) => ({ ...stop(`${lat},${lon}`, []), lat, lon });
  const PLACES: Catalog = { routes: [], stops: [at(49.8, 24.0), at(49.9, 24.1)] };
  const DOOR = -1;
  const leg = (kind: Leg["kind"], a: number, b: number, pts?: Leg["pts"]): Leg => ({
    kind,
    dep: 0,
    arr: 0,
    a,
    b,
    pts,
  });
  const journey = (legs: Leg[]): Journey => ({
    dep: 0,
    arr: 0,
    rides: 1,
    live: false,
    confidence: "live",
    backup: 0,
    legs,
  });

  test("frames the walks from the door and the stops a ride without points meets", () => {
    const j = journey([
      leg("walk", DOOR, 0, [
        [49.79, 23.98],
        [49.8, 24.0],
      ]),
      leg("ride", 0, 1),
      leg("walk", 1, DOOR, []),
    ]);

    expect(journeyBounds(j, PLACES)).toEqual([23.98, 49.79, 24.1, 49.9]);
  });

  test("frames nothing for a journey with nothing to place", () => {
    expect(journeyBounds(journey([leg("walk", DOOR, DOOR)]), PLACES)).toBeNull();
  });
});
