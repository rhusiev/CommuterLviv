import { describe, expect, test } from "vitest";
import { stopTitle } from "./catalog";

const titled = (name: string, code: string) =>
  stopTitle({ id: "s", name, code, lat: 0, lon: 0, routes: [] });

describe("stopTitle", () => {
  test("a code the name repeats is said once, as the code", () => {
    expect(titled("ТРЦ Кінг Кросс (320)", "0320")).toEqual({ name: "ТРЦ Кінг Кросс", code: "0320" });
  });

  test("a code only in the name moves out of it", () => {
    expect(titled("Кордуби (265)", "")).toEqual({ name: "Кордуби", code: "265" });
    expect(titled("ТРЦ Кінг Кросс (320-01)", "")).toEqual({ name: "ТРЦ Кінг Кросс", code: "320-01" });
  });

  test("a name without a code, or with words in brackets, is left alone", () => {
    expect(titled("ПЛ. СОБОРНА", "0074-01")).toEqual({ name: "ПЛ. СОБОРНА", code: "0074-01" });
    expect(titled("Ринок (на вимогу)", "")).toEqual({ name: "Ринок (на вимогу)", code: "" });
  });
});
