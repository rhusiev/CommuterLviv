import type { Arrival } from "./types";

/** The soonest arrival per route, in the order the routes come. The service
 * already sorts a stop's arrivals soonest first, so the first one seen for a
 * route is the one worth showing. */
export function nextPerRoute(list: Arrival[]): Arrival[] {
  const seen = new Set<number>();
  const out: Arrival[] = [];
  for (const a of list) {
    if (seen.has(a.route)) continue;
    seen.add(a.route);
    out.push(a);
  }
  return out;
}

/** How long until then, as a rider would say it. */
export function countdown(t: number, now = Date.now() / 1000): string {
  const s = t - now;
  if (s < 30) return "now";
  if (s < 90) return "1 min";
  return `${Math.round(s / 60)} min`;
}
