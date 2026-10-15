import type { Stage } from "./follow";
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
  const raw = localStorage.getItem(key);
  if (!raw) return null;
  const held = JSON.parse(raw) as Followed;
  return held.tag === tag && held.journey.arr + STALE_S > now ? held : null;
}

export function holdFollowed(followed: Followed | null) {
  if (followed === null) localStorage.removeItem(key);
  else localStorage.setItem(key, JSON.stringify(followed));
}

/** Notes how far along the journey held is; arrived, it is no longer held */
export function holdStage(stage: Stage) {
  const raw = localStorage.getItem(key);
  if (!raw) return;
  holdFollowed(stage.kind === "arrived" ? null : { ...(JSON.parse(raw) as Followed), stage });
}
