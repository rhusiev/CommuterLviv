import { useEffect, useMemo, useState } from "react";
import { shapes as fetchShapes } from "./api";
import type { Catalog, Journey, RouteShape, Shapes } from "./types";
import type { UrlState } from "./url";

type Bounds = [number, number, number, number];

/** West, south, east and north of a route's lines; null for no points */
export function bounds(shape: RouteShape): Bounds | null {
  let w = 180,
    s = 90,
    e = -180,
    n = -90;
  for (const line of shape.lines) {
    for (const [lat, lon] of line.pts) {
      w = Math.min(w, lon);
      e = Math.max(e, lon);
      s = Math.min(s, lat);
      n = Math.max(n, lat);
    }
  }
  return w > e ? null : [w, s, e, n];
}

/** What the map draws and the socket sends, by catalog position: the rides of
 * the journey shown, else the route open, else the routes picked */
export function useMapLayers({
  cat,
  tab,
  route,
  drawn,
  chosen,
  allLines,
  onError,
}: {
  cat: Catalog | null;
  tab: UrlState["tab"];
  route: number | null;
  drawn: Journey | null;
  chosen: number[];
  allLines: boolean;
  onError: (err: unknown) => void;
}) {
  const [geo, setGeo] = useState<Shapes | null>(null);

  /** While a journey is shown, only its rides are on the map */
  const journeyRoutes = useMemo(() => {
    if (!drawn) return null;
    const out = new Set<number>();
    for (const leg of drawn.legs) {
      if (leg.route !== undefined) out.add(leg.route);
    }
    return [...out].sort((a, b) => a - b);
  }, [drawn]);

  /** The socket's own filter: while one route is open it is the only one sent */
  const indexes = useMemo(
    () => journeyRoutes ?? (tab === "route" && route !== null ? [route] : chosen),
    [journeyRoutes, tab, route, chosen],
  );

  const lines = useMemo(() => {
    if (tab === "route" && route !== null) return [route];
    if (!allLines || !cat) return [];
    return cat.routes.map((_, i) => i);
  }, [tab, route, allLines, cat]);

  const fit = useMemo(() => {
    const shape = tab === "route" && route !== null ? geo?.routes[route] : null;
    return shape ? bounds(shape) : null;
  }, [tab, route, geo]);

  useEffect(() => {
    if (!lines.length || geo) return;
    void fetchShapes().then(setGeo, onError);
  }, [lines, geo, onError]);

  /** Only the stops of the routes on the map are drawn or clickable */
  const stops = useMemo(() => {
    if (!cat) return [];
    const on = new Set(indexes);
    const out: number[] = [];
    cat.stops.forEach((s, i) => {
      if (s.routes.some((r) => on.has(r))) out.push(i);
    });
    return out;
  }, [cat, indexes]);

  return { geo, indexes, lines, fit, stops };
}
