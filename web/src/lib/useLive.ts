import { useEffect, useMemo, useSyncExternalStore } from "react";
import { Live } from "./live";

/** One socket for the life of the page. The snapshot changes on connection and
 * arrivals, never on a position frame. */
export function useLive() {
  const live = useMemo(() => new Live(), []);

  useEffect(() => {
    live.open();
    return () => live.close();
  }, [live]);

  const snapshot = useSyncExternalStore(live.subscribe, live.getSnapshot);
  return { live, ...snapshot };
}
