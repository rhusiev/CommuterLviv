import { describe, expect, test } from "vitest";
import { ALL_STOPS_ZOOM, pickable, STOPS_ZOOM } from "./geo";
import type { Catalog } from "./types";
import { splitStops } from "./useMapLayers";

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
