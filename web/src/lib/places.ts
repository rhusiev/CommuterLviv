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
