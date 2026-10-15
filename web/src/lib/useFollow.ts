import { useEffect, useState } from "react";
import { Follower, Watch, type Catch, type Progress, type Seen, type Stage } from "./follow";
import { holdStage } from "./followed";
import { sample, type Live } from "./live";
import type { Catalog, Journey } from "./types";
import { heldHurry, heldSpeed } from "./walking";

const KMH_PER_MPS = 3.6;
const MS_PER_S = 1000;
const OK: Catch = { kind: "ok" };
/** How often the next connection is judged again when no fix or arrivals
 * prompt it, so a word `Watch` holds back is said when its hold ends and the
 * time left counts down. Chosen, not derived */
const JUDGE_EVERY_MS = 1000;

type Here = { lat: number; lon: number };

/** Follows `journey` from the device's own fixes until it is null: null until
 * the first fix, "denied" once the browser refuses them - a fix it could not
 * get is only waited out. The fixes go nowhere but the follower and `here`,
 * where the last one put you. `catalog` places the stops a ride calls at;
 * `stage` resumes where it was. With each fix, each word of arrivals and each
 * `JUDGE_EVERY_MS` it says whether the next ride is still caught. */
export function useFollow(
  journey: Journey | null,
  live: Live,
  catalog: Catalog | undefined,
  stage?: Stage,
): { progress: Progress | "denied" | null; caught: Catch; here: Here | null } {
  const [progress, setProgress] = useState<Progress | "denied" | null>(null);
  const [caught, setCaught] = useState<Catch>(OK);
  const [here, setHere] = useState<Here | null>(null);
  useEffect(() => {
    setProgress(null);
    setCaught(OK);
    setHere(null);
    if (!journey) return;
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
    const geo = navigator.geolocation.watchPosition(
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
        setProgress(got);
        setHere({ lat: latitude, lon: longitude });
        if (got.stage !== at) holdStage((at = got.stage));
        judge();
      },
      (err) => {
        if (err.code === err.PERMISSION_DENIED) setProgress("denied");
      },
      // Boarding is told from how fast the fixes move, so none may be a reused one
      { enableHighAccuracy: true, maximumAge: 0 },
    );
    const unsubscribe = live.subscribe(judge);
    const tick = setInterval(judge, JUDGE_EVERY_MS);
    return () => {
      navigator.geolocation.clearWatch(geo);
      unsubscribe();
      clearInterval(tick);
    };
    // `stage` only starts the follower, which then moves on from it
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [journey, live, catalog]);
  return { progress, caught, here };
}
