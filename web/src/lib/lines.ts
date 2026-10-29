import { metres } from "./geo";
import { readJson, writeJson } from "./storage";
import type { Arrival, Catalog, RouteShape } from "./types";

/** One way a line runs, by the stops it calls at in order */
export type Direction = { dir: number; stops: number[] };

/** One stop of a line: this route's next arrival there, and the vehicles whose
 * soonest stop on the line it is */
export type LineRow = { stop: number; next: Arrival | null; vehs: number[] };

/** Each way the route runs, once: of several shapes one way, the one calling
 * at the most stops, since the others are short workings of it */
export function directions(shape: RouteShape | undefined): Direction[] {
  const best = new Map<number, number[]>();
  for (const line of shape?.lines ?? []) {
    const stops = line.stops ?? [];
    if (stops.length > (best.get(line.dir)?.length ?? 0)) best.set(line.dir, stops);
  }
  return [...best].sort(([a], [b]) => a - b).map(([dir, stops]) => ({ dir, stops }));
}

/** The stops of one direction, each with what `route` has due there. A vehicle
 * is shown at the stop it reaches soonest, which is the one it is heading for;
 * one still finishing its previous trip (`planned`) is not on the line yet. */
export function lineRows(
  stops: number[],
  arrivals: Record<string, Arrival[]>,
  route: number,
): LineRow[] {
  const rows = stops.map((stop) => {
    const here = (arrivals[String(stop)] ?? []).filter((a) => a.route === route);
    return { stop, here, next: here[0] ?? null, vehs: [] as number[] };
  });
  const soonest = new Map<number, { t: number; row: number }>();
  rows.forEach(({ here }, row) => {
    for (const a of here) {
      if (a.planned) continue;
      const held = soonest.get(a.veh);
      if (!held || a.t < held.t) soonest.set(a.veh, { t: a.t, row });
    }
  });
  for (const [veh, { row }] of soonest) rows[row]!.vehs.push(veh);
  return rows.map(({ stop, next, vehs }) => ({ stop, next, vehs }));
}

/** Routes calling at any stop within `radius` metres of `at` */
export function routesNear(cat: Catalog, at: { lat: number; lon: number }, radius: number) {
  const out = new Set<number>();
  for (const s of cat.stops) {
    if (metres(at, s) <= radius) for (const r of s.routes) out.add(r);
  }
  return out;
}

/** How many lines opened lately the Lines tab offers again */
export const RECENT_LINES = 5;

const RECENT_KEY = "commuterlviv.recentLines";

/** `id` first, then the rest as they were, `RECENT_LINES` at most */
export function opened(recent: string[], id: string): string[] {
  return [id, ...recent.filter((r) => r !== id)].slice(0, RECENT_LINES);
}

/** Route ids, latest first; on this device only */
export function loadRecent(): string[] {
  const held = readJson<unknown>(RECENT_KEY);
  return Array.isArray(held) ? held.filter((r): r is string => typeof r === "string") : [];
}

export const saveRecent = (recent: string[]) => writeJson(RECENT_KEY, recent);

/** Around now means within this of it, either way. Chosen, not derived */
export const HOW_OFTEN_AROUND_S = 30 * 60;

/** A line's day at one stop: its first and last departure and, around `now`,
 * the typical gap between them in seconds - null outside its hours or where
 * it leaves too seldom to say */
export type Hours = { first: number; last: number; every: number | null };

/** `dep` is the day's departures from the stop, soonest first */
export function lineHours(dep: number[], now: number): Hours | null {
  if (dep.length === 0) return null;
  const near = dep.filter((t) => Math.abs(t - now) <= HOW_OFTEN_AROUND_S);
  const gaps = near.slice(1).map((t, i) => t - near[i]!).sort((a, b) => a - b);
  const every = gaps.length > 0 ? gaps[Math.floor(gaps.length / 2)]! : null;
  return { first: dep[0]!, last: dep.at(-1)!, every };
}
