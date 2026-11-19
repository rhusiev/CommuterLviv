import { describe, expect, test } from "vitest";
import { heldRefresh, holdRefresh, REFRESH_EVERY_S } from "./refresh";

describe("route refresh", () => {
  test("is off until asked", () => {
    expect(heldRefresh()).toBe(false);
  });

  test("is kept once asked, and off again once turned off", () => {
    holdRefresh(true);
    expect(heldRefresh()).toBe(true);

    holdRefresh(false);
    expect(heldRefresh()).toBe(false);
  });

  test("searches again every 30 s", () => {
    expect(REFRESH_EVERY_S).toBe(30);
  });
});
