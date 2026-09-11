import { useMemo } from "react";

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
