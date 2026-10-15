import { beforeEach, describe, expect, test, vi } from "vitest";
import { HURRY_KMH, heldHurry, holdHurry } from "./walking";

const kept = new Map<string, string>();
vi.stubGlobal("localStorage", {
  getItem: (k: string) => kept.get(k) ?? null,
  setItem: (k: string, v: string) => kept.set(k, v),
  removeItem: (k: string) => kept.delete(k),
});

describe("hurry pace", () => {
  beforeEach(() => kept.clear());

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
