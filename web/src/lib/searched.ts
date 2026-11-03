/** The last few things picked from a search, kept on this device only and
 *  offered again before anything is typed. A stop by its feed id, so a new
 *  catalog finds it again; a place by its name and point. */
export type Searched = { stop: string } | { name: string; lat: number; lon: number };

const KEY = "commuterlviv.searched";
/** As many as are offered: a short list read at a glance, not a history */
export const SEARCHED_KEPT = 3;

const same = (a: Searched, b: Searched) =>
  "stop" in a ? "stop" in b && a.stop === b.stop : "name" in b && a.name === b.name;

export function heldSearched(): Searched[] {
  try {
    const held: unknown = JSON.parse(localStorage.getItem(KEY) ?? "[]");
    return Array.isArray(held) ? (held as Searched[]).slice(0, SEARCHED_KEPT) : [];
  } catch {
    return [];
  }
}

/** `picked` first, without its earlier copy, the oldest dropped past the cap */
export function holdSearched(picked: Searched): Searched[] {
  const next = [picked, ...heldSearched().filter((s) => !same(s, picked))].slice(0, SEARCHED_KEPT);
  try {
    localStorage.setItem(KEY, JSON.stringify(next));
  } catch {
    // Not kept: the list just starts over next time
  }
  return next;
}
