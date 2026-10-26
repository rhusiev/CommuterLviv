import { describe, expect, test } from "vitest";
import { pointLabel, stopTitle } from "./catalog";
import { t } from "./i18n";

const titled = (name: string, code: string) =>
  stopTitle({ id: "s", name, code, lat: 0, lon: 0, routes: [] });

describe("stopTitle", () => {
  test("a code the name repeats is said once, as the name says it", () => {
    expect(titled("ТРЦ Кінг Кросс (320)", "0320")).toEqual({ name: "ТРЦ Кінг Кросс", code: "320" });
    expect(titled("Площа Франка (311)", "0280")).toEqual({ name: "Площа Франка", code: "311" });
  });

  test("a code only in the name moves out of it", () => {
    expect(titled("Кордуби (265)", "")).toEqual({ name: "Кордуби", code: "265" });
    expect(titled("ТРЦ Кінг Кросс (320-01)", "")).toEqual({ name: "ТРЦ Кінг Кросс", code: "320-01" });
  });

  test("a name without a code, or with words in brackets, is left alone, the code unpadded", () => {
    expect(titled("ПЛ. СОБОРНА", "0074-01")).toEqual({ name: "ПЛ. СОБОРНА", code: "74-01" });
    expect(titled("Ринок", "0")).toEqual({ name: "Ринок", code: "0" });
    expect(titled("Ринок (на вимогу)", "")).toEqual({ name: "Ринок (на вимогу)", code: "" });
  });
});

describe("pointLabel", () => {
  const stop = (name: string, lat: number, lon: number) => ({ id: name, name, code: "", lat, lon, routes: [] });
  // 1e-3 degrees of latitude is 111 m
  const CATALOG = { routes: [], stops: [stop("Ринок (100)", 49.842, 24.03), stop("Підвальна", 49.845, 24.03)] };

  test("names a point by the nearest stop, without its code", () => {
    expect(pointLabel(CATALOG, { lat: 49.8431, lon: 24.03 })).toBe(t.nearStop("Ринок"));
    expect(pointLabel(CATALOG, { lat: 49.8441, lon: 24.03 })).toBe(t.nearStop("Підвальна"));
  });

  test("gives the coordinates of a point no stop is near", () => {
    expect(pointLabel(CATALOG, { lat: 49.836, lon: 24.03 })).toBe("49.8360, 24.0300");
  });
});
