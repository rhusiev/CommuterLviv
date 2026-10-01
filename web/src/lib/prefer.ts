import type { Backup, Journey } from "./types";

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

/** When the journey is over, a minute on foot counting as two: what a tie on
 * changes or backups is settled by, so a ride from the door beats a slightly
 * earlier one behind a long walk */
const effort = (j: Journey) => j.arr + walking(j);

/** The whole walk has no changes and no backup to speak of, so it goes last
 * wherever those are what is asked for */
const rideOr = (j: Journey, v: number) => (j.rides === 0 ? Infinity : v);

const SCORE: Record<Prefer, (j: Journey) => number[]> = {
  fastest: (j) => [j.arr, j.rides, walking(j)],
  walk: (j) => [walking(j), j.arr, j.rides],
  changes: (j) => [rideOr(j, j.rides), effort(j)],
  reliable: (j) => [rideOr(j, -j.backup), effort(j), j.rides],
};

/** Lowest score first, a tie settled by the next number */
const order = <T>(items: T[], score: (x: T) => number[]): T[] =>
  items
    .map((x) => [score(x), x] as const)
    .sort(([a], [b]) => {
      for (const [n, x] of a.entries()) {
        const y = b[n]!;
        if (x !== y) return x - y;
      }
      return 0;
    })
    .map(([, x]) => x);

export const ranked = (options: Journey[], p: Prefer) => order(options, SCORE[p]);

/** What helps nothing if a planned vehicle does not come: its rides on them */
const planned = (b: Backup) => b.rides.filter((r) => r.planned).length;

const BACKUP_SCORE: Record<Prefer, (b: Backup) => number[]> = {
  fastest: (b) => [b.arr, b.rides.length, b.walk],
  walk: (b) => [b.walk, b.arr, b.rides.length],
  changes: (b) => [b.rides.length, b.arr + b.walk],
  reliable: (b) => [planned(b), b.rides.filter((r) => !r.live).length, b.arr + b.walk],
};

/** The `n` backups worth showing first, soonest first as sent: the best by
 *  what is preferred, then the best by each other preference, so one is
 *  there should what is preferred be the thing that fails, then the next
 *  best by what is preferred */
export function shortlist(backups: Backup[], p: Prefer, n = 4): Backup[] {
  const picks = new Set<Backup>();
  for (const q of [p, ...PREFERS.filter((q) => q !== p)]) {
    const best = order(backups, BACKUP_SCORE[q])[0];
    if (best && picks.size < n) picks.add(best);
  }
  for (const b of order(backups, BACKUP_SCORE[p])) {
    if (picks.size >= n) break;
    picks.add(b);
  }
  return backups.filter((b) => picks.has(b));
}
