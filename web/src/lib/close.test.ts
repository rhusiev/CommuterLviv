import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { api } from "./api";
import { heldClose, holdClose } from "./prefer";

describe("close options", () => {
  const realFetch = globalThis.fetch;
  beforeEach(() => localStorage.removeItem("commuterlviv.close"));
  afterEach(() => {
    globalThis.fetch = realFetch;
  });

  test("are off until turned on, and stay as kept", () => {
    expect(heldClose()).toBe(false);

    holdClose(true);

    expect(heldClose()).toBe(true);
  });

  test("are asked for in the search only when on", async () => {
    const asked: string[] = [];
    globalThis.fetch = async (url: string | URL | Request) => {
      asked.push(String(url));
      return new Response(JSON.stringify({ t: 0, options: [] }));
    };

    await api.plan([49.8, 24.0], [49.81, 24.04], null, 4.5, null, [], true);
    await api.plan([49.8, 24.0], [49.81, 24.04], null, 4.5, null);

    expect(asked[0]).toContain("&close=1");
    expect(asked[1]).not.toContain("close");
  });
});
