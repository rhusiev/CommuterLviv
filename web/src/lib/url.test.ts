import { describe, expect, test } from "vitest";
import { tabOf } from "./url";

describe("tabOf", () => {
  test("reads the tabs that were folded into Mine as Mine", () => {
    expect(tabOf("times")).toBe("mine");
    expect(tabOf("saved")).toBe("mine");
  });

  test("reads the old one-line tab as the Lines tab", () => {
    expect(tabOf("route")).toBe("lines");
  });

  test("keeps a tab that still exists and opens the map for anything else", () => {
    expect(tabOf("plan")).toBe("plan");
    expect(tabOf("lines")).toBe("lines");
    expect(tabOf("mine")).toBe("mine");
    expect(tabOf(null)).toBe("map");
    expect(tabOf("constructor")).toBe("map");
  });
});
