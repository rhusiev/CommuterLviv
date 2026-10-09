import { describe, expect, test } from "vitest";
import { score, words } from "./match";

const of = (q: string, name: string) => score(words(q), words(name));

describe("match", () => {
  test("words match in any order, by prefix", () => {
    expect(of("шевч пл", "Площа Шевченка")).toBeGreaterThan(0);
    expect(of("ринок", "Площа Ринок")).toBeGreaterThan(0);
  });

  test("й and ї fold, apostrophes are not typed", () => {
    expect(of("иорд", "Йорданська")).toBe(of("йорд", "Йорданська"));
    expect(of("обєднання", "Обʼєднання")).toBeGreaterThan(0);
  });

  test("one slip is forgiven in a longer word, none in a short one", () => {
    expect(of("стрийска", "Стрийська")).toBeGreaterThan(0);
    expect(of("рнк", "Ринок")).toBe(0);
    expect(of("xyz", "Площа Ринок")).toBe(0);
  });

  test("a prefix outranks a slip", () => {
    expect(of("стрийсь", "Стрийська")).toBeGreaterThan(of("стрийска", "Стрийська"));
  });
});
