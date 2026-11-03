import { beforeEach, describe, expect, test } from "vitest";
import { heldSearched, holdSearched, SEARCHED_KEPT } from "./searched";

describe("the recent picks of a search", () => {
  beforeEach(() => localStorage.removeItem("commuterlviv.searched"));

  test("are the latest first, a pick again moved up rather than listed twice", () => {
    holdSearched({ stop: "s1" });
    holdSearched({ name: "Park", lat: 49.82, lon: 24.02 });
    holdSearched({ stop: "s1" });

    expect(heldSearched()).toEqual([{ stop: "s1" }, { name: "Park", lat: 49.82, lon: 24.02 }]);
  });

  test("keep only the last few", () => {
    for (let i = 0; i < SEARCHED_KEPT + 2; i++) holdSearched({ stop: `s${i}` });

    expect(heldSearched().map((s) => ("stop" in s ? s.stop : ""))).toEqual(["s4", "s3", "s2"]);
  });

  test("start over from anything unreadable", () => {
    localStorage.setItem("commuterlviv.searched", "{not json");

    expect(heldSearched()).toEqual([]);
  });
});
