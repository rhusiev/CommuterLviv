import { useEffect, useState } from "react";
import { Follower, Watch, type Catch, type Progress, type Seen, type Stage } from "./follow";
import { holdStage } from "./followed";
import { sample, type Live } from "./live";
import { watchHere } from "./position";
import type { Catalog, Journey } from "./types";
import { heldHurry, heldSpeed } from "./walking";

const KMH_PER_MPS = 3.6;
const MS_PER_S = 1000;
const OK: Catch = { kind: "ok" };
/** How often the next connection is judged again when no fix or arrivals
 * prompt it, so a word `Watch` holds back is said when its hold ends and the
 * time left counts down. Chosen, not derived */
const JUDGE_EVERY_MS = 1000;

type Said = {
  /** What it was said of: anything else is not followed yet */
  journey: Journey | null;
  catalog: Catalog | undefined;
  progress: Progress | "denied" | null;
  caught: Catch;
  /** The last fix, for drawing the walk under way from it */
  here: Here | null;
};

type Here = { lat: number; lon: number; t: number };

/** Follows `journey` from the device's own fixes until it is null: null until
 * the first fix, "denied" once the browser refuses them - a fix it could not
 * get is only waited out. The fixes go nowhere but the follower. `catalog`
 * places the stops a ride calls at; `stage` resumes where it was. With each fix,
 * each word of arrivals and each `JUDGE_EVERY_MS` it says whether the next ride
 * is still caught. */
export function useFollow(
  journey: Journey | null,
  live: Live,
  catalog: Catalog | undefined,
  stage?: Stage,
): { progress: Progress | "denied" | null; caught: Catch; here: Here | null } {
  const [said, setSaid] = useState<Said>({ journey, catalog, progress: null, caught: OK, here: null });
  useEffect(() => {
    if (!journey) return;
    const fresh: Said = { journey, catalog, progress: null, caught: OK, here: null };
    const say = (next: Partial<Said>) =>
      setSaid((was) => ({
        ...(was.journey === journey && was.catalog === catalog ? was : fresh),
        ...next,
      }));
    const setProgress = (progress: Said["progress"]) => say({ progress });
    const setCaught = (caught: Catch) => say({ caught });
    const follower = new Follower(journey, catalog, stage);
    const watch = new Watch();
    let at = follower.progress.stage;
    const judge = () => {
      const mps = heldSpeed() / KMH_PER_MPS;
      const hurryMps = Math.max(heldHurry() ?? 0, heldSpeed()) / KMH_PER_MPS;
      const due = (stop: number, veh: number) =>
        live.arrivals[String(stop)]?.find((a) => a.veh === veh)?.t;
      const now = Date.now() / MS_PER_S;
      const reach = follower.reach(due, now, mps, hurryMps);
      setCaught(watch.update(reach, follower.progress.stage, now));
    };
    const leave = watchHere(
      (pos) => {
        // Where the map draws each vehicle at this moment, which is all the
        // follower has to tell the one ridden from the one beside it
        const now = performance.now();
        const seen: Seen[] = [];
        for (const [id, v] of live.vehicles) {
          const [lat, lon] = sample(v, now);
          seen.push({ id, route: v.route, lat, lon });
        }
        const { latitude, longitude, accuracy } = pos.coords;
        const got = follower.update(
          { lat: latitude, lon: longitude, accuracy, t: pos.timestamp },
          seen,
        );
        say({ progress: got, here: { lat: latitude, lon: longitude, t: pos.timestamp / MS_PER_S } });
        if (got.stage !== at) holdStage((at = got.stage));
        judge();
      },
      (err) => {
        if (err.code === err.PERMISSION_DENIED) setProgress("denied");
      },
    );
    const unsubscribe = live.subscribe(judge);
    const tick = setInterval(judge, JUDGE_EVERY_MS);
    return () => {
      leave();
      unsubscribe();
      clearInterval(tick);
    };
    // `stage` only starts the follower, which then moves on from it
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [journey, live, catalog]);
  const current = said.journey === journey && said.catalog === catalog;
  return current
    ? { progress: said.progress, caught: said.caught, here: said.here }
    : { progress: null, caught: OK, here: null };
}
