import { useMemo } from "react";

import type { Catalog } from "./types";

/** Feed id to position in the catalog. Everything but storage addresses a route
 * or a stop by position; only what is stored is an id. */
export const useIndex = (items: { id: string }[] | undefined) =>
  useMemo(
    () => new Map((items ?? []).map((x, i) => [x.id, i] as const)),
    [items],
  );

/** Stored ids back to positions. One the city has dropped since does not
 * resolve, and is left out. */
export const usePositions = (
  index: Map<string, number>,
  ids: Iterable<string>,
) =>
  useMemo(
    () =>
      [...ids]
        .map((id) => index.get(id))
        .filter((i): i is number => i !== undefined),
    [ids, index],
  );

/** A stop's name, or none for a position this catalog lacks: the server sends
 * -1 for a stop missing from it, and a newer catalog may be longer */
export const stopName = (catalog: Catalog, i: number) =>
  catalog.stops[i]?.name ?? "";
