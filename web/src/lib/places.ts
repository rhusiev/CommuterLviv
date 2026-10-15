import { MIN_TYPED, score, words } from "./match";
import type { Place } from "./types";

/** The name is the identity server-side and the list is written whole, so every
 * change here is the old list with one name taken out and at most one put back.
 * A rename is exactly that, which is why it lands as one atomic write. */

export const dropped = (places: Place[], name: string): Place[] =>
  places.filter((p) => p.name !== name);

export const saved = (places: Place[], name: string, lat: number, lon: number): Place[] => [
  ...dropped(places, name),
  { name, lat, lon },
];

export const renamed = (places: Place[], was: Place, name: string): Place[] =>
  saved(dropped(places, was.name), name, was.lat, was.lon);

/** The saved places whose names answer the query, best first and shorter names
 * first among equals, as stops are ranked */
export function matching(places: Place[], query: string): Place[] {
  const q = words(query);
  if (q.join("").length < MIN_TYPED) return [];
  return places
    .map((p) => ({ p, s: score(q, words(p.name)) }))
    .filter(({ s }) => s > 0)
    .sort((a, b) => b.s - a.s || a.p.name.length - b.p.name.length)
    .map(({ p }) => p);
}
