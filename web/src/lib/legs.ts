import type { Progress, Stage } from "./follow";
import { metres } from "./geo";
import type { Journey } from "./types";

/** One line of a journey's plan: a leg, or the wait at a stop before a ride.
 *  `leg` is the journey leg it belongs to, the ride waited for on a wait */
export type Row =
  | { kind: "walk"; leg: number; dep: number; arr: number; to: number; change: boolean }
  | { kind: "wait"; leg: number; dep: number; arr: number; at: number }
  | { kind: "ride"; leg: number; dep: number; arr: number; route?: number; a: number; b: number };

/** A shorter gap before a ride is not worth a line of its own */
export const WAIT_MIN_S = 60;

/** The seconds between leg `i` leaving and the leg before it arriving: the
 *  wait at the stop when `i` is a ride. Nothing comes before the first leg */
export function waitBefore(j: Journey, i: number): number {
  return i > 0 ? j.legs[i]!.dep - j.legs[i - 1]!.arr : 0;
}

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
    if (waitBefore(j, i) >= WAIT_MIN_S)
      out.push({ kind: "wait", leg: i, dep: j.legs[i - 1]!.arr, arr: leg.dep, at: leg.a });
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

/** The vehicles a journey's rides are planned on */
export function riddenBy(journey: Journey | null): Set<number> {
  const ids = new Set<number>();
  for (const leg of journey?.legs ?? []) if (leg.veh != null) ids.add(leg.veh);
  return ids;
}

/** The journey as it is being walked: the walk under way drawn from where the
 *  device is, along the last `left` metres of its line, and setting off now.
 *  Every other stage leaves it as planned. */
export function walkingFrom(
  j: Journey,
  progress: Progress,
  here: { lat: number; lon: number; t: number },
): Journey {
  const { stage, left } = progress;
  if (stage.kind !== "walk" || progress.astray) return j;
  const leg = j.legs[stage.leg]!;
  const pts = leg.pts ?? [];
  const rest: [number, number][] = [];
  let gone = 0;
  for (let i = pts.length - 1; i > 0; i--) {
    rest.unshift(pts[i]!);
    const [lat, lon] = pts[i]!;
    const [lat0, lon0] = pts[i - 1]!;
    gone += metres({ lat, lon }, { lat: lat0, lon: lon0 });
    if (gone >= left) break;
  }
  const walking = { ...leg, dep: Math.min(here.t, leg.arr), pts: [[here.lat, here.lon] as [number, number], ...rest] };
  return { ...j, legs: j.legs.map((l, i) => (i === stage.leg ? walking : l)) };
}

