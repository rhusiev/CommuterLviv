import { along, GRACE_S, type Progress, type Stage } from "./follow";
import { metres } from "./geo";
import type { Arrival, Journey, Leg } from "./types";

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
  return rowsOf(j.legs);
}

/** `rows` of legs already carrying their times */
function rowsOf(legs: Leg[]): Row[] {
  const out: Row[] = [];
  legs.forEach((leg, i) => {
    if (leg.kind === "walk") {
      // Consecutive walks are folded before they are sent, so a walk with a
      // ride either side is the change itself
      const change = leg.b >= 0 && i > 0 && i < legs.length - 1;
      out.push({ kind: "walk", leg: i, dep: leg.dep, arr: leg.arr, to: leg.b, change });
      return;
    }
    if (i > 0 && leg.dep - legs[i - 1]!.arr >= WAIT_MIN_S)
      out.push({ kind: "wait", leg: i, dep: legs[i - 1]!.arr, arr: leg.dep, at: leg.a });
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

/** What a followed plan's times are worked out from, all of it already on the
 *  device */
export type LivePlan = {
  /** Unix seconds */
  now: number;
  /** Where the follower is, or null while that is not known */
  stage: Stage | null;
  /** Metres left on the leg under way */
  left: number;
  /** Predicted arrivals by catalog stop index, as the socket sends them */
  arrivals: Record<string, Arrival[]>;
};

/** The followed journey's rows, every time still to come taken from live
 *  predictions and how far along the device is; the legs done keep the times
 *  they were planned with. Nothing here asks the service. */
export function liveRows(j: Journey, plan: LivePlan): Row[] {
  return rowsOf(liveLegs(j, plan));
}

/** The followed journey's legs with their times still to come made live, as
 *  `liveRows` describes. */
export function liveLegs(j: Journey, plan: LivePlan): Leg[] {
  const { stage } = plan;
  if (stage === null || stage.kind === "arrived") return j.legs;
  const at = (stop: number): Arrival[] => plan.arrivals[String(stop)] ?? [];
  const out: Leg[] = [];
  /** When the leg before the one being built gets in */
  let inAt = plan.now;
  j.legs.forEach((leg, i) => {
    if (i < stage.leg) {
      out.push(leg);
      inAt = leg.arr;
      return;
    }
    if (leg.kind === "walk") {
      const arr = i === stage.leg ? plan.now + walkRest(leg, plan.left) : inAt + walkTime(leg);
      out.push(i === stage.leg ? { ...leg, arr } : { ...leg, dep: inAt, arr });
      inAt = arr;
      return;
    }
    if (i === stage.leg) {
      // Waiting at the stop: the ride is picked from the predictions where the
      // device is now, not from where the walk was to get in
      if (stage.kind === "wait") {
        const waiting = leavingAt(at(leg.a), leg.route, leg.veh ?? null, plan.now);
        const dep = waiting === undefined ? leg.dep : Math.max(waiting.t, plan.now);
        const arr = waiting === undefined
          ? leg.arr
          : (arrivalTime(at(leg.b), waiting.veh) ?? dep + rideTime(leg));
        out.push({ ...leg, dep, arr });
        inAt = arr;
        return;
      }
      // A ride under way keeps when it was boarded; only its arrival moves
      const veh = stage.kind === "ride" ? stage.veh : null;
      const arr = veh === null ? leg.arr : (arrivalTime(at(leg.b), veh) ?? leg.arr);
      out.push({ ...leg, arr });
      inAt = arr;
      return;
    }
    const leaving = leavingAt(at(leg.a), leg.route, leg.veh ?? null, inAt);
    const dep = leaving === undefined
      ? Math.max(leg.dep, inAt)
      : Math.max(leaving.t, inAt);
    const arr = leaving === undefined
      ? dep + rideTime(leg)
      : (arrivalTime(at(leg.b), leaving.veh) ?? dep + rideTime(leg));
    out.push({ ...leg, dep, arr });
    inAt = arr;
  });
  return out;
}

/** Seconds the rest of `leg` takes at the pace it was planned at. The service
 *  times a walk over the footpaths, slopes and all, so its own seconds are kept
 *  and shared out by distance rather than assumed flat. */
export function walkRest(leg: Leg, left: number): number {
  const planned = walkTime(leg);
  const length = along(leg.pts ?? []);
  // Without a line to share the planned seconds along, the service's own pace
  // is all there is to go by; a service that sends no line cannot be followed
  if (length <= 0) return left / FLAT_MPS;
  return planned * Math.min(1, Math.max(0, left / length));
}

/** The service's walking pace on the level, m/s: `SPEED` in `walk.py` */
const FLAT_MPS = 1.25;

const walkTime = (leg: Leg) => Math.max(0, leg.arr - leg.dep);
const rideTime = walkTime;

const arrivalTime = (list: Arrival[], veh: number) =>
  list.find((a) => a.veh === veh)?.t;

/** The arrival of `route` to leave at or after `from`, preferring the planned
 *  vehicle `veh` whenever it is still catchable */
function leavingAt(
  list: Arrival[],
  route: number | undefined,
  veh: number | null,
  from: number,
): Arrival | undefined {
  const ofRoute = route === undefined ? [] : list.filter((a) => a.route === route);
  if (veh !== null) {
    const held = ofRoute.find((a) => a.veh === veh && a.t >= from - GRACE_S);
    if (held) return held;
  }
  return ofRoute.find((a) => a.t >= from);
}

/** How much sooner a plan that still works must arrive to be followed instead:
 *  chosen, not derived - enough to matter, not so little that a jumping
 *  prediction moves the rider */
export const BETTER_S = 120;

/** `options` with the one to follow in place of a plan arriving at
 *  `currentArr`: the best the planner offers when the plan is `broken`, else
 *  one reaching the door at least `BETTER_S` sooner. Null when the plan still
 *  is the best. */
export function betterPlan(
  currentArr: number,
  options: Journey[],
  broken: boolean,
): Journey | null {
  const first = options[0];
  if (!first) return null;
  if (broken || currentArr === Infinity) return first;
  return first.arr <= currentArr - BETTER_S ? first : null;
}

/** Whether `b` is the plan `a` already is, so following it would change
 *  nothing */
export function samePlan(a: Journey, b: Journey): boolean {
  if (a.dep !== b.dep || a.arr !== b.arr || a.legs.length !== b.legs.length) return false;
  return a.legs.every((l, i) => {
    const o = b.legs[i]!;
    return (
      l.kind === o.kind &&
      l.a === o.a &&
      l.b === o.b &&
      l.route === o.route &&
      l.dep === o.dep &&
      l.arr === o.arr
    );
  });
}

type Here = { lat: number; lon: number; t: number };

/** The journey as it is under way, for the map: the legs already done left
 *  off, and a walk under way, unless strayed from, drawn from where the device
 *  is. Arrived, it is left whole. */
export function underWay(j: Journey, progress: Progress, here: Here): Journey {
  const { stage } = progress;
  if (stage.kind === "arrived") return j;
  const legs = j.legs.slice(stage.leg);
  if (stage.kind === "walk" && !progress.astray) legs[0] = walkingFrom(legs[0]!, progress.left, here);
  return { ...j, legs };
}

/** A walk drawn from `here` along the last `left` metres of its line, setting
 *  off now */
function walkingFrom(leg: Leg, left: number, here: Here): Leg {
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
  return { ...leg, dep: Math.min(here.t, leg.arr), pts: [[here.lat, here.lon] as [number, number], ...rest] };
}

