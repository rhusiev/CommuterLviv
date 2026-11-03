import { beforeEach, describe, expect, test } from "vitest";
import { heldAvoid, holdAvoid } from "./prefer";

describe("the vehicle types left out of a search", () => {
  beforeEach(() => localStorage.removeItem("commuterlviv.avoid"));

  test("are none until some are held, and come back as held", () => {
    expect(heldAvoid()).toEqual([]);

    holdAvoid(["tram"]);

    expect(heldAvoid()).toEqual(["tram"]);
  });

  test("are never all of them, which the service would refuse", () => {
    holdAvoid(["bus", "tram", "trolleybus"]);

    expect(heldAvoid()).toEqual([]);
  });

  test("drop a name the service does not know", () => {
    localStorage.setItem("commuterlviv.avoid", "boat,tram");

    expect(heldAvoid()).toEqual(["tram"]);
  });
});
