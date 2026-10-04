import { useEffect, useState } from "react";
import { Follower, type Progress, type Seen } from "./follow";
import { sample, type Live } from "./live";
import type { Catalog, Journey } from "./types";

/** Follows `journey` from the device's own fixes until it is null: null until
 * the first fix, "denied" once the browser refuses them - a fix it could not
 * get is only waited out. The fixes go nowhere but the follower. `catalog`
 * places the stops a ride calls at. */
export function useFollow(
  journey: Journey | null,
  live: Live,
  catalog: Catalog | undefined,
): Progress | "denied" | null {
  const [progress, setProgress] = useState<Progress | "denied" | null>(null);
  useEffect(() => {
    setProgress(null);
    if (!journey) return;
    const follower = new Follower(journey, catalog);
    const watch = navigator.geolocation.watchPosition(
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
        setProgress(
          follower.update({ lat: latitude, lon: longitude, accuracy, t: pos.timestamp }, seen),
        );
      },
      (err) => {
        if (err.code === err.PERMISSION_DENIED) setProgress("denied");
      },
      // Boarding is told from how fast the fixes move, so none may be a reused one
      { enableHighAccuracy: true, maximumAge: 0 },
    );
    return () => navigator.geolocation.clearWatch(watch);
  }, [journey, live, catalog]);
  return progress;
}
