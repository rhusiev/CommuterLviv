import { describe, expect, test, vi } from "vitest";
import { countdown } from "./eta";
import { t as txt } from "./i18n";

// The strings module picks a language from `localStorage` as it loads, which
// Node does not have. Hoisted above the imports
vi.hoisted(() => vi.stubGlobal("localStorage", { getItem: () => null }));

describe("eta", () => {
  // Pins the bug where `t` was read as a countdown, not an instant
  test("the countdown is against the clock, not from zero", () => {
    const now = Date.UTC(2026, 8, 8, 10, 0) / 1000;
    const t = now;

    // Against the dictionary: the thresholds are what this tests
    expect(countdown(t, now)).toBe(txt.now);
    expect(countdown(t + 29, now)).toBe(txt.now);
    expect(countdown(t + 60, now)).toBe(txt.oneMinute);
    expect(countdown(t + 90, now)).toBe(txt.minutes(2));
    expect(countdown(t + 600, now)).toBe(txt.minutes(10));
    expect(countdown(t - 300, now)).toBe(txt.now);
  });
});
