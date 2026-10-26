/** Following a journey as it is travelled, from the device's own fixes. Nothing
 * here leaves the device: the fixes are compared against the journey's legs and
 * the vehicles the socket already sends. `mobile/lib/src/follow.dart` is the
 * same machine, and its tests are this file's too.
 *
 * Boarding is the step that has to be right. Standing at a stop beside a tram
 * looks exactly like sitting in it, so a ride counts as boarded only once the
 * fixes move along the ride's line faster than anyone walks. Only then is the
 * vehicle picked: the one of the leg's route keeping pace with the fixes.
 *
 * Ahead of every ride still to board, the fixes and the predictions say
 * whether it is still caught: walking to its stop at the usual pace, only by
 * hurrying - now, or off the ride before it - or not at all. */

import type { Catalog, Journey, Leg } from "./types";
import { HURRY_KMH } from "./walking";

export type Fix = { lat: number; lon: number; accuracy: number; t: number };

/** A vehicle where the map draws it at the time of the fix */
export type Seen = { id: number; route: number; lat: number; lon: number };

export type Stage =
  | { kind: "walk"; leg: number }
  | { kind: "wait"; leg: number }
  /** `veh` is the wire id of the vehicle ridden, null while none keeps pace */
  | { kind: "ride"; leg: number; veh: number | null }
  | { kind: "arrived" };

export type Progress = {
  stage: Stage;
  /** Metres still to go on the current leg, along it */
  left: number;
  /** Further from the leg's line than a fix's error explains */
  astray: boolean;
  /** Carried on past the stop to get off at */
  passed: boolean;
  /** On the ride, past its last stop before the one to get off at */
  soon: boolean;
};

/** When a vehicle gets to a stop, Unix seconds, while the predictions say */
export type Due = (stop: number, veh: number) => number | undefined;

/** When the next ride to board leaves, and when the device gets to its stop at
 * the usual and at the hurrying pace, all Unix seconds: setting off on foot at
 * `from` for the `walk` metres there. `live`: `dep` is a prediction for a
 * tracked vehicle, not the timetable. */
export type Reach = {
  leg: number;
  dep: number;
  live: boolean;
  from: number;
  walk: number;
  usual: number;
  hurried: number;
};

/** The next ride to board, on time or not: `riding` warns ahead of a change
 * from the ride under way, which hurrying cannot help yet. `kmh` is the pace
 * hurrying needs (`needKmh`), null once missed. */
export type Catch =
  | { kind: "ok" }
  | { kind: "hurry" | "missed"; leg: number; dep: number; riding: boolean; kmh: number | null };

/** A tracked vehicle missed by this little is still caught: the driver waits
 * for somebody waving or running. `GRACE` in `commuterlviv/plan/scan.py`. */
export const GRACE_S = 10;
/** Seconds ahead, and the slack a change needs that far ahead: `CHANGE_AHEAD`
 * and `CHANGE_SLACK` in `commuterlviv/plan/scan.py` */
const CHANGE_AHEAD = [60, 210, 450, 750, 1050, 1500, 2250];
const CHANGE_SLACK = [60, 90, 150, 180, 210, 270, 300];
/** A change is broken by either vehicle's forecast missing, a walk to a stop
 * only by the one vehicle's, so it keeps this share of a change's slack.
 * Chosen, not derived */
const MARGIN_SHARE = 0.5;
const KMH_PER_MPS = 3.6;
/** A worse word on the connection holds this long before it is said: two of
 * the service's five-second frames, so one jumpy prediction is not news.
 * Chosen, not derived. */
const HOLD_S = 10;
/** Closer to leaving than this a prediction is good to some 22 s
 * (docs/service.md), so a worse word is said at once */
const NEAR_S = 120;

/** A fix vaguer than this says nothing about which side of a tram it is on */
const MAX_ACCURACY_M = 50;
/** Close enough to a stop or the door to be at it */
const ARRIVE_M = 40;
/** How far from a leg's line a fix on it can still land */
const ON_LINE_M = 50;
/** Further than this off the line is off the journey */
const ASTRAY_M = 100;
/** A brisk walk or a jog, but no vehicle in motion */
const WALK_MAX_MPS = 2.5;
/** Ridden this far along the line, faster than walking, is boarded */
const BOARD_M = 100;
/** Fixes it takes to believe that, so one jump of the GPS is not a ride */
const BOARD_FIXES = 3;
/** A vehicle further than this along the line from the fixes is another one.
 * Generous: the map draws a vehicle from its last fix, 10 s old at median, and
 * dead-reckons only part of the way on from there. */
const MATCH_M = 150;
/** The share of the fixes' way along the line a vehicle must have gone too,
 * over the same fixes, to be the one carrying them. Its drawn position moves
 * in a step per frame, so this asks for less than all of it. */
const PACE_SHARE = 0.5;
/** A vehicle this far from the ride's line is not on it */
const VEHICLE_OFF_M = 60;
/** Fixes in a row the ridden vehicle may fall out of step before another is
 * looked for */
const LOST_FIXES = 5;
/** Moving no faster than walking for this long, at the stop, is off */
const ALIGHT_S = 15;
/** This far beyond the stop, faster than walking, is carried past it */
const PASSED_M = 150;
/** Where a ride does not say which stops it calls at, this close to the stop
 * to get off at is getting ready for it. Chosen, not derived: about a stop's
 * spacing in the city centre. */
const SOON_M = 400;
/** What is kept of the fixes: enough for `BOARD_M` at walking pace */
const HISTORY_MS = 60_000;

const EARTH_M = 6_371_000;
const RAD = Math.PI / 180;

type XY = { x: number; y: number };
/** Where a fix and a vehicle seen with it were, in metres along a line */
type Beside = { user: number; veh: number };

/** Flat metres around the journey's start, which over a city is exact enough */
function plane(lat0: number, lon0: number) {
  const kx = EARTH_M * RAD * Math.cos(lat0 * RAD);
  const ky = EARTH_M * RAD;
  return (lat: number, lon: number): XY => ({ x: (lon - lon0) * kx, y: (lat - lat0) * ky });
}

const dist = (a: XY, b: XY) => Math.hypot(a.x - b.x, a.y - b.y);

class Line {
  readonly cum: number[] = [0];
  constructor(readonly xy: XY[]) {
    for (let i = 1; i < xy.length; i++) this.cum.push(this.cum[i - 1]! + dist(xy[i - 1]!, xy[i]!));
  }

  get length() {
    return this.cum[this.cum.length - 1]!;
  }

  get end() {
    return this.xy[this.xy.length - 1]!;
  }

  /** Metres along the line to the point nearest `p`, and how far off it `p` is */
  project(p: XY): { s: number; off: number } {
    if (this.xy.length === 1) return { s: 0, off: dist(p, this.xy[0]!) };
    let best = { s: 0, off: Infinity };
    for (let i = 1; i < this.xy.length; i++) {
      const a = this.xy[i - 1]!;
      const b = this.xy[i]!;
      const dx = b.x - a.x;
      const dy = b.y - a.y;
      const len2 = dx * dx + dy * dy;
      const k = len2 ? Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2)) : 0;
      const off = Math.hypot(p.x - a.x - k * dx, p.y - a.y - k * dy);
      if (off < best.off) best = { s: this.cum[i - 1]! + k * Math.sqrt(len2), off };
    }
    return best;
  }
}

type Sample = { t: number; at: XY; seen: { id: number; route: number; at: XY }[] };

/** Every leg must carry its line; an older service sends none */
export const followable = (j: Journey) => j.legs.every((l) => (l.pts?.length ?? 0) > 0);

/** A journey begun on board starts on its ride, the rest walking or waiting */
export const start = (j: Journey): Stage => {
  const first = j.legs[0];
  if (first?.kind !== "ride") return { kind: "walk", leg: 0 };
  return j.aboard ? { kind: "ride", leg: 0, veh: first.veh ?? null } : { kind: "wait", leg: 0 };
};

export class Follower {
  private readonly legs: Leg[];
  private readonly lines: Line[];
  private readonly at: (lat: number, lon: number) => XY;
  private readonly routes: Set<number>;
  /** Metres along each leg from which it is time to get ready to get off */
  private readonly ready: number[];
  private stage: Stage;
  private history: Sample[] = [];
  /** Fixes in a row the ridden vehicle has been out of step */
  private misses = 0;
  /** Got within `ARRIVE_M` of the ride's last stop */
  private reached = false;
  private last: Progress;

  /** `catalog` places the stops a ride calls at; without it, or without them,
   * getting ready goes by `SOON_M`. `stage` resumes a journey followed before. */
  constructor(journey: Journey, catalog?: Catalog, stage?: Stage) {
    this.legs = journey.legs;
    const [lat0, lon0] = this.legs[0]?.pts?.[0] ?? [0, 0];
    this.at = plane(lat0, lon0);
    this.lines = this.legs.map((l) => new Line((l.pts ?? []).map(([lat, lon]) => this.at(lat, lon))));
    this.routes = new Set(this.legs.flatMap((l) => (l.route === undefined ? [] : [l.route])));
    this.ready = this.legs.map((l, i) => this.readyAt(l, this.lines[i]!, catalog));
    this.stage = stage ?? start(journey);
    const left = this.stage.kind === "arrived" ? 0 : (this.lines[this.stage.leg]?.length ?? 0);
    this.last = { stage: this.stage, left, astray: false, passed: false, soon: false };
  }

  /** Reaching the stop before the one to get off at - the boarding stop, for a
   * ride of one stop - or else `SOON_M` short of the end */
  private readyAt(leg: Leg, line: Line, catalog?: Catalog): number {
    if (!catalog || !leg.stops) return line.length - SOON_M;
    const s = catalog.stops[leg.stops.length ? leg.stops[leg.stops.length - 1]! : leg.a]!;
    return line.project(this.at(s.lat, s.lon)).s - ARRIVE_M;
  }

  get progress() {
    return this.last;
  }

  /** When the next ride to board leaves and when the device gets to its stop,
   * at `mps` and at `hurryMps` metres a second. Null with no ride ahead, while
   * waiting at its stop - the vehicle is in sight there - and while the vehicle
   * ridden is not known or not predicted to the stop to get off at. */
  reach(due: Due, now: number, mps: number, hurryMps: number): Reach | null {
    const stage = this.stage;
    if (stage.kind === "wait" || stage.kind === "arrived") return null;
    const r = this.legs.findIndex((l, k) => k > stage.leg && l.kind === "ride");
    if (r < 0) return null;
    let from = now;
    let walk = 0;
    if (stage.kind === "walk") walk = this.last.left;
    else {
      const off = stage.veh === null ? undefined : due(this.legs[stage.leg]!.b, stage.veh);
      if (off === undefined) return null;
      from = off;
    }
    for (let k = stage.leg + 1; k < r; k++) walk += this.lines[k]!.length;
    const next = this.legs[r]!;
    const tracked = next.veh == null ? undefined : due(next.a, next.veh);
    return {
      leg: r,
      dep: tracked ?? next.dep,
      live: tracked !== undefined,
      from,
      walk,
      usual: from + walk / mps,
      hurried: from + walk / hurryMps,
    };
  }

  /** Takes a fix and the vehicles drawn at its time, and says where on the
   * journey that puts the device. A vague fix changes nothing, and nor does one
   * older than the last: a phone's two sources of fixes interleave. */
  update(fix: Fix, vehicles: Seen[]): Progress {
    const older = this.history.length > 0 && fix.t <= this.now.t;
    if (fix.accuracy > MAX_ACCURACY_M || this.stage.kind === "arrived" || older) return this.last;
    const seen = vehicles
      .filter((v) => this.routes.has(v.route))
      .map((v) => ({ id: v.id, route: v.route, at: this.at(v.lat, v.lon) }));
    this.history.push({ t: fix.t, at: this.at(fix.lat, fix.lon), seen });
    this.history = this.history.filter((h) => fix.t - h.t <= HISTORY_MS);
    let passed = false;
    if (this.stage.kind === "walk") passed = this.walk(this.stage.leg);
    else if (this.stage.kind === "wait") this.board(this.stage.leg);
    else passed = this.ride(this.stage.leg, this.stage.veh);
    this.last = this.report(passed);
    return this.last;
  }

  private report(passed: boolean): Progress {
    if (this.stage.kind === "arrived") {
      return { stage: this.stage, left: 0, astray: false, passed: false, soon: false };
    }
    const line = this.lines[this.stage.leg]!;
    const { s, off } = line.project(this.now.at);
    const soon = this.stage.kind === "ride" && s >= this.ready[this.stage.leg]!;
    return { stage: this.stage, left: Math.max(0, line.length - s), astray: off > ASTRAY_M, passed, soon };
  }

  private get now() {
    return this.history[this.history.length - 1]!;
  }

  private go(stage: Stage) {
    this.stage = stage;
    // What was seen on one leg proves nothing about the next, except that a
    // walk to a stop may already be the ride from it
    if (stage.kind !== "wait") this.history = [this.now];
    this.misses = 0;
    this.reached = false;
  }

  /** The leg after `i`, as the stage that starts it */
  private next(i: number): Stage {
    const leg = this.legs[i + 1];
    if (!leg) return { kind: "arrived" };
    return leg.kind === "ride" ? { kind: "wait", leg: i + 1 } : { kind: "walk", leg: i + 1 };
  }

  private walk(i: number): boolean {
    const ride = this.legs[i + 1]?.kind === "ride";
    // A walk ending at a stop may turn into the ride before the fixes ever
    // came within `ARRIVE_M` of it
    if (ride && this.board(i + 1)) return false;
    if (dist(this.now.at, this.lines[i]!.end) <= ARRIVE_M) {
      this.go(this.next(i));
      return false;
    }
    return this.legs[i - 1]?.kind === "ride" && this.brisk(i);
  }

  /** Whether the fixes have ridden away along leg `i`'s line; if so the stage
   * is the ride, on the vehicle that kept pace if one did */
  private board(i: number): boolean {
    const line = this.lines[i]!;
    const along = this.history.map((h) => ({ h, ...line.project(h.at) }));
    const last = along[along.length - 1]!;
    // The latest fix still behind by `BOARD_M`, it and everything after it on
    // the line
    let from = -1;
    for (let k = along.length - 1; k >= 0; k--) {
      if (along[k]!.off > ON_LINE_M) break;
      if (last.s - along[k]!.s >= BOARD_M) {
        from = k;
        break;
      }
    }
    if (from < 0 || along.length - from < BOARD_FIXES) return false;
    const took = (last.h.t - along[from]!.h.t) / 1000;
    if (took <= 0 || BOARD_M / took <= WALK_MAX_MPS) return false;
    const leg = this.legs[i]!;
    this.go({ kind: "ride", leg: i, veh: this.pace(line, leg, this.history.slice(from)) });
    return true;
  }

  /** The vehicle of the leg's route keeping pace with these fixes: the one
   * whose median gap along the line is smallest, within `MATCH_M`. The vehicle
   * the plan named wins whenever it qualifies. */
  private pace(line: Line, leg: Leg, samples: Sample[]): number | null {
    const tracks = new Map<number, Beside[]>();
    for (const h of samples) {
      const s = line.project(h.at).s;
      for (const v of h.seen) {
        if (v.route !== leg.route) continue;
        const p = line.project(v.at);
        if (p.off > VEHICLE_OFF_M) continue;
        const track = tracks.get(v.id) ?? [];
        track.push({ user: s, veh: p.s });
        tracks.set(v.id, track);
      }
    }
    let best: number | null = null;
    let bestGap = MATCH_M;
    for (const [id, track] of tracks) {
      if (!keepsUp(track, samples.length)) continue;
      const gap = median(track.map((b) => Math.abs(b.veh - b.user)));
      if (gap > MATCH_M) continue;
      if (id === leg.veh) return id;
      if (gap <= bestGap) {
        best = id;
        bestGap = gap;
      }
    }
    return best;
  }

  private ride(i: number, veh: number | null): boolean {
    const line = this.lines[i]!;
    const leg = this.legs[i]!;
    const here = line.project(this.now.at).s;
    const v = veh === null ? undefined : this.now.seen.find((x) => x.id === veh);
    // The route too: a pruned vehicle's id can come back on another one
    const inStep =
      v !== undefined && v.route === leg.route && Math.abs(line.project(v.at).s - here) <= MATCH_M;
    this.misses = inStep ? 0 : this.misses + 1;
    if (this.misses >= LOST_FIXES) {
      const found = this.pace(line, leg, this.history);
      this.stage = { kind: "ride", leg: i, veh: found };
      this.misses = 0;
    }
    const gap = dist(this.now.at, line.end);
    if (gap <= ARRIVE_M) this.reached = true;
    if (this.reached && gap <= ARRIVE_M && this.still()) {
      this.go(this.next(i));
      return false;
    }
    return this.reached && gap > PASSED_M;
  }

  /** No faster than walking over the last `ALIGHT_S` */
  private still(): boolean {
    const now = this.now;
    for (let k = this.history.length - 1; k >= 0; k--) {
      const h = this.history[k]!;
      const took = (now.t - h.t) / 1000;
      if (took >= ALIGHT_S) return dist(now.at, h.at) <= WALK_MAX_MPS * took;
    }
    return false;
  }

  /** Away from the walk's start by `PASSED_M`, faster than walking: still on
   * the vehicle that should have been left there */
  private brisk(i: number): boolean {
    const startAt = this.lines[i]!.xy[0]!;
    const now = this.now;
    const away = dist(now.at, startAt);
    if (away < PASSED_M) return false;
    for (let k = this.history.length - 1; k >= 0; k--) {
      const h = this.history[k]!;
      const took = (now.t - h.t) / 1000;
      if (took > 0 && away - dist(h.at, startAt) >= PASSED_M) return PASSED_M / took > WALK_MAX_MPS;
    }
    return false;
  }
}

/** Seen beside at least half the fixes, and gone at least `PACE_SHARE` as far
 * along the line as they did. A tram left standing at the stop is close to the
 * first fixes of a ride on the next one, and only this tells them apart. */
function keepsUp(track: Beside[], fixes: number): boolean {
  if (track.length * 2 < fixes) return false;
  const first = track[0]!;
  const last = track[track.length - 1]!;
  return last.veh - first.veh >= (last.user - first.user) * PACE_SHARE;
}

function median(xs: number[]): number {
  const s = [...xs].sort((a, b) => a - b);
  const m = s.length >> 1;
  return s.length % 2 ? s[m]! : (s[m - 1]! + s[m]!) / 2;
}

/** `xs` ascending; flat past both ends */
function interp(x: number, xs: number[], ys: number[]): number {
  const k = xs.findIndex((v) => v >= x);
  if (k === 0) return ys[0]!;
  if (k < 0) return ys[ys.length - 1]!;
  const share = (x - xs[k - 1]!) / (xs[k]! - xs[k - 1]!);
  return ys[k - 1]! + share * (ys[k]! - ys[k - 1]!);
}

/** Seconds to be at a stop before a vehicle forecast to leave `ahead` s from
 * now does, so that a forecast missing the usual amount still finds it there */
export const margin = (ahead: number) => MARGIN_SHARE * interp(ahead, CHANGE_AHEAD, CHANGE_SLACK);

/** The pace in km/h that walks `metres` setting off at `from` to be at the stop
 * `margin` before `dep`, forecast at `now` - or right at `dep` should the
 * margin take more than a run (`HURRY_KMH.max`). Rounded up to the step speeds
 * are set in; null with nothing to walk, or when not even that leaves any time. */
export function needKmh(metres: number, from: number, dep: number, now = from): number | null {
  const pace = (s: number) => (s > 0 ? (metres / s) * KMH_PER_MPS : Infinity);
  let kmh = pace(dep - margin(dep - now) - from);
  if (kmh > HURRY_KMH.max) kmh = pace(dep - from);
  if (!Number.isFinite(kmh) || kmh <= 0) return null;
  return Math.ceil(kmh / HURRY_KMH.step) * HURRY_KMH.step;
}

/** Metres along `pts`, [lat, lon] pairs */
export function along(pts: [number, number][]): number {
  const [lat0, lon0] = pts[0] ?? [0, 0];
  const at = plane(lat0, lon0);
  return new Line(pts.map(([lat, lon]) => at(lat, lon))).length;
}

/** `needKmh` of an option caught only by hurrying, as it was planned */
export function plannedKmh(j: Journey): number | null {
  const [walk, ride] = j.legs;
  if (walk?.kind !== "walk" || ride?.kind !== "ride") return null;
  return needKmh(along(walk.pts ?? []), walk.dep, ride.dep);
}

/** Caught at the usual pace; else at the hurrying one, or for a tracked vehicle
 * within `GRACE_S` of it; else missed */
export function judge(r: Reach): "ok" | "hurry" | "missed" {
  if (r.usual <= r.dep) return "ok";
  return r.hurried <= r.dep || (r.live && r.hurried - GRACE_S <= r.dep) ? "hurry" : "missed";
}

const OK: Catch = { kind: "ok" };
const WORSE = { ok: 0, hurry: 1, missed: 2 } as const;

/** What to say of the next connection, steadied: a better word is said at
 * once, a worse one only once it has held for `HOLD_S`, or at once within
 * `NEAR_S` of leaving */
export class Watch {
  private said: Catch = OK;
  /** A worse word than the one said, and since when it has held */
  private coming: { kind: "hurry" | "missed"; leg: number; since: number } | null = null;

  /** `reach` is the follower's answer at `stage`, `now` Unix seconds */
  update(reach: Reach | null, stage: Stage, now: number): Catch {
    const said = this.said;
    if (reach === null) {
      // Waiting at the stop of a connection missed still has it missed: the
      // vehicle there is a later one
      const missed = said.kind === "missed" && stage.kind === "wait" && stage.leg === said.leg;
      this.said = missed ? said : OK;
      this.coming = null;
      return this.said;
    }
    if (said.kind !== "ok" && said.leg !== reach.leg) this.said = OK;
    const kind = judge(reach);
    const kmh = kind === "hurry" ? needKmh(reach.walk, reach.from, reach.dep, now) : null;
    const word: Catch =
      kind === "ok" ? OK : { kind, leg: reach.leg, dep: reach.dep, riding: stage.kind === "ride", kmh };
    if (kind === "ok" || WORSE[kind] <= WORSE[this.said.kind]) {
      this.said = word;
      this.coming = null;
      return word;
    }
    if (this.coming?.kind !== kind || this.coming.leg !== reach.leg) {
      this.coming = { kind, leg: reach.leg, since: now };
    }
    if (now - this.coming.since >= HOLD_S || reach.dep - now <= NEAR_S) {
      this.said = word;
      this.coming = null;
    }
    return this.said;
  }
}
