import { beforeEach, describe, expect, test, vi } from "vitest";
import { heldFollowed, holdFollowed, holdStage, type Followed } from "./followed";

const kept = new Map<string, string>();
vi.stubGlobal("localStorage", {
  getItem: (k: string) => kept.get(k) ?? null,
  setItem: (k: string, v: string) => kept.set(k, v),
  removeItem: (k: string) => kept.delete(k),
});

const TAG = '"city-1"';
const ARR = 10_000;
const followed: Followed = {
  journey: { dep: 0, arr: ARR, rides: 0, live: false, confidence: "live", backup: 0, legs: [] },
  to: { lat: 49.84, lon: 24.03 },
  tag: TAG,
};

describe("the journey followed", () => {
  beforeEach(() => kept.clear());

  test("is there after a reload, where it had got to", () => {
    holdFollowed(followed);
    holdStage({ kind: "wait", leg: 1 });

    expect(heldFollowed(TAG, ARR)).toEqual({ ...followed, stage: { kind: "wait", leg: 1 } });
  });

  test("is gone once ended or arrived", () => {
    holdFollowed(followed);
    holdFollowed(null);
    expect(heldFollowed(TAG, ARR)).toBeNull();

    holdFollowed(followed);
    holdStage({ kind: "arrived" });
    expect(heldFollowed(TAG, ARR)).toBeNull();
  });

  test("is dropped on another catalog, whose positions it does not use", () => {
    holdFollowed(followed);

    expect(heldFollowed('"city-2"', ARR)).toBeNull();
  });

  test("is none when what is stored is not a journey", () => {
    for (const junk of ["{not json", "null", '{"tag":"\\"city-1\\""}']) {
      kept.set("commuterlviv.following", junk);

      expect(heldFollowed(TAG, ARR)).toBeNull();
    }
  });

  test("is dropped hours after it should have arrived", () => {
    holdFollowed(followed);

    expect(heldFollowed(TAG, ARR + 3 * 3600)).toBeNull();
  });
});
