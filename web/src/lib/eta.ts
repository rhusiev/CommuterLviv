import type { Arrival } from "./types";
import { t } from "./i18n";

/** The soonest arrival per route. Relies on the service sorting a stop's
 * arrivals soonest first. */
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

export function countdown(at: number, now = Date.now() / 1000): string {
  const s = at - now;
  if (s < 30) return t.now;
  if (s < 90) return t.oneMinute;
  return t.minutes(Math.round(s / 60));
}
