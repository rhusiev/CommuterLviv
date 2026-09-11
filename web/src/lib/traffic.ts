import { useEffect, useState } from "react";
import { api, streets as fetchStreets } from "./api";
import type { Streets, Traffic } from "./types";

/** How fast the streets are running, for as long as the view is open.

The streets themselves are a quarter of a megabyte that never changes, so they
are fetched once and kept across openings; the numbers are small and are asked
for again every minute while the view is up, and not at all while it is down. */

export const PERIOD = 60_000;

/** The ramp, as maplibre reads it: a ratio of actual to timetabled travel time,
 * then the colour for it. 1 is exactly the timetable. */
export const RAMP: [number, string][] = [
  [0.85, "#22c55e"],
  [1.0, "#a3e635"],
  [1.15, "#facc15"],
  [1.3, "#fb923c"],
  [1.6, "#ef4444"],
];

/** The streets and their current numbers, side by side and the same length */
export type Pace = { lines: Streets["lines"]; ratio: Traffic["ratio"] };

let held: Streets | null = null;

export function useTraffic(open: boolean): Pace | null {
  const [lines, setLines] = useState<Streets | null>(held);
  const [now, setNow] = useState<Traffic | null>(null);

  useEffect(() => {
    if (!open || held) return;
    let gone = false;
    void fetchStreets().then((got) => {
      held = got;
      if (!gone) setLines(got);
    }, console.warn);
    return () => {
      gone = true;
    };
  }, [open]);

  useEffect(() => {
    if (!open) return;
    let gone = false;
    const ask = () => void api.traffic().then((got) => !gone && setNow(got), console.warn);
    ask();
    const id = setInterval(ask, PERIOD);
    return () => {
      gone = true;
      clearInterval(id);
    };
  }, [open]);

  return lines && now ? { lines: lines.lines, ratio: now.ratio } : null;
}
