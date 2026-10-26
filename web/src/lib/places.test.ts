import { describe, expect, test } from "vitest";
import { matching, renamed, replaces, samePlace, saved, taken } from "./places";

const at = (name: string) => ({ name, lat: 49.84, lon: 24.03 });
const names = (q: string, ...saved: string[]) => matching(saved.map(at), q).map((p) => p.name);

describe("matching", () => {
  test("matches saved names the way stops are matched", () => {
    expect(names("роб", "Дім", "Робота")).toEqual(["Робота"]);
    expect(names("мами д", "Дім мами", "Дім")).toEqual(["Дім мами"]);
  });

  test("ranks closer matches first, and shorter names first among equals", () => {
    expect(names("спорт", "Спортзал біля роботи", "Спортзал", "Спорт")).toEqual([
      "Спорт",
      "Спортзал",
      "Спортзал біля роботи",
    ]);
    expect(names("hone", "Phone shop", "Home")).toEqual(["Phone shop", "Home"]);
  });

  test("waits for a second letter", () => {
    expect(names("д", "Дім")).toEqual([]);
  });
});

describe("samePlace", () => {
  test("takes a point within a few metres for the place, and one a street away not", () => {
    const home = at("Дім");
    expect(samePlace({ lat: home.lat + 5e-5, lon: home.lon - 5e-5 }, home)).toBe(true);
    expect(samePlace({ lat: home.lat + 1e-3, lon: home.lon }, home)).toBe(false);
  });
});

describe("renamed and saved", () => {
  const list = [at("Дім"), { name: "Робота", lat: 49.8, lon: 24 }, at("Спорт")];

  test("a renamed place keeps its row", () => {
    expect(renamed(list, list[1]!, "Офіс").map((p) => p.name)).toEqual(["Дім", "Офіс", "Спорт"]);
  });

  test("a place saved anew under its name is replaced where it stood", () => {
    expect(saved(list, "Робота", 49.9, 24.1)).toEqual([list[0], { name: "Робота", lat: 49.9, lon: 24.1 }, list[2]]);
    expect(saved(list, "Нове", 49.9, 24.1).map((p) => p.name)).toEqual(["Дім", "Робота", "Спорт", "Нове"]);
  });
});

describe("taken", () => {
  const list = [at("Дім"), at("Робота")];

  test("is a name another place goes by, compared trimmed as the server stores it", () => {
    expect(taken(list, "  Робота ", list[0])).toBe(true);
    expect(taken(list, "Робота", list[1])).toBe(false);
    expect(taken(list, "Офіс", list[0])).toBe(false);
  });
});

describe("replaces", () => {
  test("is a name in use somewhere else, not the same place saved again", () => {
    const home = at("Дім");
    expect(replaces([home], "Дім ", { lat: home.lat + 1e-3, lon: home.lon })).toBe(true);
    expect(replaces([home], "Дім", { lat: home.lat, lon: home.lon })).toBe(false);
    expect(replaces([home], "Робота", { lat: home.lat + 1e-3, lon: home.lon })).toBe(false);
  });
});
