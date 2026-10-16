import { describe, expect, test } from "vitest";
import { matching } from "./places";

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
