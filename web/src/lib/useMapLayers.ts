import { useEffect, useMemo, useState } from "react";
import { shapes as fetchShapes } from "./api";
import type { Catalog, Journey, RouteShape, Shapes } from "./types";

type Bounds = [number, number, number, number];

/** West, south, east and north of `[lat, lon]` points; null for none */
function boundsOf(points: Iterable<readonly [number, number]>): Bounds | null {
  let w = 180,
    s = 90,
    e = -180,
    n = -90;
  for (const [lat, lon] of points) {
    w = Math.min(w, lon);
    e = Math.max(e, lon);
    s = Math.min(s, lat);
    n = Math.max(n, lat);
  }
  return w > e ? null : [w, s, e, n];
}

/** The bounds of a route's lines */
export function bounds(shape: RouteShape): Bounds | null {
  return boundsOf(shape.lines.flatMap((line) => line.pts));
}

/** The bounds of what a journey's legs go along, and of the stops they meet
 *  at - a leg from an older service may have no points */
export function journeyBounds(j: Journey, cat: Catalog): Bounds | null {
  const stops = j.legs
    .flatMap((leg) => [cat.stops[leg.a], cat.stops[leg.b]])
    .flatMap((stop) => (stop ? [[stop.lat, stop.lon] as const] : []));
  return boundsOf([...j.legs.flatMap((leg) => leg.pts ?? []), ...stops]);
}

/** What the map draws and the socket sends, by catalog position: the line
 * open, else the rides of the journey shown, else the routes picked */
export function useMapLayers({
  cat,
  route,
  drawn,
  framed,
  chosen,
  allLines,
  onError,
}: {
  cat: Catalog | null;
  /** The line open in the Lines tab, while that tab is shown */
  route: number | null;
  drawn: Journey | null;
  /** The journey the camera frames once it is shown, in place of a line */
  framed: Journey | null;
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
    () => (route !== null ? [route] : (journeyRoutes ?? chosen)),
    [journeyRoutes, route, chosen],
  );

  const lines = useMemo(() => {
    if (route !== null) return [route];
    if (!allLines || !cat) return [];
    return cat.routes.map((_, i) => i);
  }, [route, allLines, cat]);

  const lineFit = useMemo(() => {
    const shape = route !== null ? geo?.routes[route] : null;
    return shape ? bounds(shape) : null;
  }, [route, geo]);
  // Apart, so the shapes arriving do not frame the journey again
  const journeyFit = useMemo(
    () => (framed && cat ? journeyBounds(framed, cat) : null),
    [framed, cat],
  );
  const fit = route !== null ? lineFit : journeyFit;

  useEffect(() => {
    if (!lines.length || geo) return;
    void fetchShapes().then(setGeo, onError);
  }, [lines, geo, onError]);

  const { stops, faint } = useMemo(() => splitStops(cat, indexes), [cat, indexes]);

  return { geo, indexes, lines, fit, stops, faint };
}

/** The stops a route on the map calls at, and every other one, which is drawn
 * faint and only from close in */
export function splitStops(cat: Catalog | null, routes: number[]) {
  const on = new Set(routes);
  const stops: number[] = [];
  const faint: number[] = [];
  cat?.stops.forEach((s, i) => (s.routes.some((r) => on.has(r)) ? stops : faint).push(i));
  return { stops, faint };
}
