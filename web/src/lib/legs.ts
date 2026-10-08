import type { Stage } from "./follow";
import type { Journey } from "./types";

/** One line of a journey's plan: a leg, or the wait at a stop before a ride.
 *  `leg` is the journey leg it belongs to, the ride waited for on a wait */
export type Row =
  | { kind: "walk"; leg: number; dep: number; arr: number; to: number; change: boolean }
  | { kind: "wait"; leg: number; dep: number; arr: number; at: number }
  | { kind: "ride"; leg: number; dep: number; arr: number; route?: number; a: number; b: number };

/** A shorter gap before a ride is not worth a line of its own */
export const WAIT_MIN_S = 60;

/** The journey's legs in order, with a wait wherever a ride leaves a minute or
 *  more after the leg before it got there */
export function rows(j: Journey): Row[] {
  const out: Row[] = [];
  j.legs.forEach((leg, i) => {
    if (leg.kind === "walk") {
      // Consecutive walks are folded before they are sent, so a walk with a
      // ride either side is the change itself
      const change = leg.b >= 0 && i > 0 && i < j.legs.length - 1;
      out.push({ kind: "walk", leg: i, dep: leg.dep, arr: leg.arr, to: leg.b, change });
      return;
    }
    const before = i > 0 ? j.legs[i - 1]!.arr : null;
    if (before !== null && leg.dep - before >= WAIT_MIN_S)
      out.push({ kind: "wait", leg: i, dep: before, arr: leg.dep, at: leg.a });
    out.push({ kind: "ride", leg: i, dep: leg.dep, arr: leg.arr, route: leg.route, a: leg.a, b: leg.b });
  });
  return out;
}

/** The row `stage` is at: its own kind on its leg, else the leg's last row -
 *  the ride, when its wait was too short to list. -1 once arrived */
export function current(list: Row[], stage: Stage): number {
  if (stage.kind === "arrived") return -1;
  const same = list.findIndex((r) => r.leg === stage.leg && r.kind === stage.kind);
  if (same >= 0) return same;
  const next = list.findIndex((r) => r.leg > stage.leg);
  return (next < 0 ? list.length : next) - 1;
}
