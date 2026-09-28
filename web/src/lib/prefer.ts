import type { Journey } from "./types";

export const PREFERS = ["fastest", "walk", "changes", "reliable"] as const;
export type Prefer = (typeof PREFERS)[number];

const key = "commuterlviv.prefer";

export function heldPrefer(): Prefer {
  const held = localStorage.getItem(key);
  return PREFERS.find((p) => p === held) ?? "fastest";
}

export function holdPrefer(p: Prefer) {
  localStorage.setItem(key, p);
}

const walking = (j: Journey) =>
  j.legs.reduce((s, l) => s + (l.kind === "walk" ? l.arr - l.dep : 0), 0);

/** The whole walk has no changes and no backup to speak of, so it goes last
 * wherever those are what is asked for */
const rideOr = (j: Journey, v: number) => (j.rides === 0 ? Infinity : v);

const SCORE: Record<Prefer, (j: Journey) => number[]> = {
  fastest: (j) => [j.arr, j.rides, walking(j)],
  walk: (j) => [walking(j), j.arr, j.rides],
  changes: (j) => [rideOr(j, j.rides), j.arr, walking(j)],
  reliable: (j) => [rideOr(j, -j.backup), j.arr, j.rides],
};

export function ranked(options: Journey[], p: Prefer): Journey[] {
  const score = SCORE[p];
  return options
    .map((j) => [score(j), j] as const)
    .sort(([a], [b]) => {
      for (const [n, x] of a.entries()) {
        const y = b[n]!;
        if (x !== y) return x - y;
      }
      return 0;
    })
    .map(([, j]) => j);
}
