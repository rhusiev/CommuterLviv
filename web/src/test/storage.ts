import { beforeEach, vi } from "vitest";

// Node has no `localStorage`, and the strings module reads it as it loads, so
// every test file gets an in-memory one before its imports, emptied per test
const kept = new Map<string, string>();
vi.stubGlobal("localStorage", {
  getItem: (k: string) => kept.get(k) ?? null,
  setItem: (k: string, v: string) => kept.set(k, v),
  removeItem: (k: string) => kept.delete(k),
});
beforeEach(() => kept.clear());
