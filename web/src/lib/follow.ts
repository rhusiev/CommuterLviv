/** Following a journey as it is travelled, from the device's own fixes. Nothing
 * here leaves the device: the fixes are compared against the journey's legs and
 * the vehicles the socket already sends. `mobile/lib/src/follow.dart` is the
 * same machine, and its tests are this file's too.
 *
 * Boarding is the step that has to be right. Standing at a stop beside a tram
 * looks exactly like sitting in it, so a ride counts as boarded only once the
 * fixes move along the ride's line faster than anyone walks. Only then is the
 * vehicle picked: the one of the leg's route keeping pace with the fixes. */

import type { Journey, Leg } from "./types";

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
};

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

export const start = (j: Journey): Stage =>
  j.legs[0]?.kind === "ride" ? { kind: "wait", leg: 0 } : { kind: "walk", leg: 0 };

export class Follower {
  private readonly legs: Leg[];
  private readonly lines: Line[];
  private readonly at: (lat: number, lon: number) => XY;
  private readonly routes: Set<number>;
  private stage: Stage;
  private history: Sample[] = [];
  /** Fixes in a row the ridden vehicle has been out of step */
  private misses = 0;
  /** Got within `ARRIVE_M` of the ride's last stop */
  private reached = false;
  private last: Progress;

  constructor(journey: Journey) {
    this.legs = journey.legs;
    const [lat0, lon0] = this.legs[0]?.pts?.[0] ?? [0, 0];
    this.at = plane(lat0, lon0);
    this.lines = this.legs.map((l) => new Line((l.pts ?? []).map(([lat, lon]) => this.at(lat, lon))));
    this.routes = new Set(this.legs.flatMap((l) => (l.route === undefined ? [] : [l.route])));
    this.stage = start(journey);
    this.last = { stage: this.stage, left: this.lines[0]?.length ?? 0, astray: false, passed: false };
  }

  get progress() {
    return this.last;
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
    if (this.stage.kind === "arrived") return { stage: this.stage, left: 0, astray: false, passed: false };
    const line = this.lines[this.stage.leg]!;
    const { s, off } = line.project(this.now.at);
    return { stage: this.stage, left: Math.max(0, line.length - s), astray: off > ASTRAY_M, passed };
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
