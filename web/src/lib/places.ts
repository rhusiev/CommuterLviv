import { MIN_TYPED, score, words } from "./match";
import type { Place } from "./types";

/** A place shown on the map: one saved, or one found by name with the line under it */
export type Shown = Place & { where?: string };

/** The same place: 1e-4 degrees is about 11 m */
export const samePlace = (a: { lat: number; lon: number }, b: Place) =>
  Math.abs(a.lat - b.lat) < 1e-4 && Math.abs(a.lon - b.lon) < 1e-4;

/** The name is the identity server-side, which keeps the last of a repeated
 * name, and the list is written whole. So a place keeps its row when it is
 * saved anew or renamed, and a rename onto a name another place goes by is
 * refused by the caller (`taken`) rather than sent, as it would drop that one. */

export const dropped = (places: Place[], name: string): Place[] =>
  places.filter((p) => p.name !== name);

/** The place saved under `name`, replacing the one of that name where it stood */
export const saved = (places: Place[], name: string, lat: number, lon: number): Place[] => {
  const place = { name, lat, lon };
  return places.some((p) => p.name === name)
    ? places.map((p) => (p.name === name ? place : p))
    : [...places, place];
};

export const renamed = (places: Place[], was: Place, name: string): Place[] =>
  places.map((p) => (p.name === was.name ? { ...p, name } : p));

/** Another saved place goes by `name`, compared trimmed as the server stores it */
export const taken = (places: Place[], name: string, except?: Place): boolean =>
  places.some((p) => p.name !== except?.name && p.name.trim() === name.trim());

/** Saving `name` at the point would replace a place of that name somewhere else */
export const replaces = (places: Place[], name: string, at: { lat: number; lon: number }): boolean =>
  places.some((p) => p.name.trim() === name.trim() && !samePlace(at, p));

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
