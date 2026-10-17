import type { Stage } from "./follow";
import { readJson, writeJson } from "./storage";
import type { Journey } from "./types";

/** A journey being followed, kept across a reload until it is ended, arrived
 *  or replaced: where it goes, for searching again, and the catalog its stop
 *  and route positions belong to */
export type Followed = {
  journey: Journey;
  to: { lat: number; lon: number };
  tag: string;
  /** How far along it was, as the follower last said */
  stage?: Stage;
};

const key = "commuterlviv.following";
/** Past its arrival by this much, a journey left followed is long over. Chosen,
 *  not derived */
const STALE_S = 2 * 3600;

/** The journey followed before the page loaded, unless the city has moved on to
 *  another catalog or it is stale */
export function heldFollowed(tag: string, now: number): Followed | null {
  const held = readJson<Followed>(key);
  return held?.tag === tag && held.journey?.arr + STALE_S > now ? held : null;
}

export function holdFollowed(followed: Followed | null) {
  if (followed === null) localStorage.removeItem(key);
  else writeJson(key, followed);
}

/** Notes how far along the journey held is; arrived, it is no longer held */
export function holdStage(stage: Stage) {
  const held = readJson<Followed>(key);
  if (!held) return;
  holdFollowed(stage.kind === "arrived" ? null : { ...held, stage });
}
