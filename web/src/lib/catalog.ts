import { useMemo } from "react";

import type { Catalog, Stop } from "./types";

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

/** The city writes most stops' codes into their names too, "ТРЦ Кінг Кросс
 * (320)", and some stops' codes only there */
const CODE_IN_NAME = /\s*\(([\d-]+)\)$/;

/** The feed pads its codes with zeros the names do not: "0074-01" for "74-01" */
const PADDING = /^0+(?=\d)/;

/** A stop's name and code for where both are shown, the code said once and as
 * the names say it. The name's own code comes first: the feed's disagrees with
 * it for a few stops, "Площа Франка (311)" coded 0280 */
export const stopTitle = (s: Stop) => {
  const inName = CODE_IN_NAME.exec(s.name);
  if (!inName) return { name: s.name, code: s.code.replace(PADDING, "") };
  return { name: s.name.slice(0, inName.index), code: inName[1]! };
};
