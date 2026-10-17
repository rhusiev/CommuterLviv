import { describe, expect, test } from "vitest";
import { HURRY_KMH, heldHurry, holdHurry } from "./walking";

describe("hurry pace", () => {
  test("is off until set", () => {
    expect(heldHurry()).toBeNull();
  });

  test("is kept once set, and off again once turned off", () => {
    holdHurry(9);
    expect(heldHurry()).toBe(9);

    holdHurry(null);
    expect(heldHurry()).toBeNull();
  });

  test("past what the service takes is off", () => {
    holdHurry(HURRY_KMH.max + HURRY_KMH.step);

    expect(heldHurry()).toBeNull();
  });
});
