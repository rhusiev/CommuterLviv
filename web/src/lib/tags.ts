import { clock } from "./eta";
import type { Leg } from "./types";

export type Tag = { lat: number; lon: number; text: string };

/** Times within this far of each other share a pill: one stop at every zoom */
const SAME_STOP_M = 25;
const M_PER_DEGREE_LAT = 111320;
const M_PER_DEGREE_LON = 71770; // at Lviv's latitude
/** A shorter walk gets no times of its own: somebody standing at the stop
 *  would read it as a walk from a minute to the same minute */
export const SHORT_WALK_S = 60;

/** One pill per stop of the picked journey: getting off and getting on share
 * a pill reading off → on, or one time when both are the same minute. `legs`
 * are the ones drawn, each with a path */
export function journeyTags(legs: Leg[]): Tag[] {
  type Group = { lat: number; lon: number; off: number[]; on: number[] };
  const groups: Group[] = [];
  const at = (lat: number, lon: number): Group => {
    for (const g of groups) {
      if (
        Math.abs(lat - g.lat) * M_PER_DEGREE_LAT < SAME_STOP_M &&
        Math.abs(lon - g.lon) * M_PER_DEGREE_LON < SAME_STOP_M
      )
        return g;
    }
    const g: Group = { lat, lon, off: [], on: [] };
    groups.push(g);
    return g;
  };
  for (const leg of legs) {
    if (leg.kind === "walk" && leg.arr - leg.dep < SHORT_WALK_S) continue;
    const pts = leg.pts!;
    const s = pts[0]!;
    const e = pts[pts.length - 1]!;
    at(s[0], s[1]).on.push(leg.dep);
    at(e[0], e[1]).off.push(leg.arr);
  }
  const out: Tag[] = [];
  for (const g of groups) {
    const off = clock(Math.max(...g.off));
    const on = clock(Math.min(...g.on));
    if (g.off.length && g.on.length && off !== on) {
      out.push({ lat: g.lat, lon: g.lon, text: `${off} → ${on}` });
    } else {
      out.push({ lat: g.lat, lon: g.lon, text: g.off.length ? off : on });
    }
    for (const extra of [...g.off.slice(0, -1), ...g.on.slice(1)]) {
      out.push({ lat: g.lat, lon: g.lon, text: clock(extra) });
    }
  }
  return out;
}
