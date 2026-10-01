import { useEffect, useMemo, useSyncExternalStore } from "react";
import { Live } from "./live";

/** Set across the reload a new catalog forces, so the page can say why */
const RENEWED = "commuterlviv.renewed";

/** Whether this page was reloaded onto a new catalog; true once */
export function takeRenewed() {
  const was = sessionStorage.getItem(RENEWED) !== null;
  sessionStorage.removeItem(RENEWED);
  return was;
}

/** One socket for the life of the page. The snapshot changes on connection and
 * arrivals, never on a position frame. A new catalog reloads the page, which
 * keeps what it shows in its URL by id. */
export function useLive() {
  const live = useMemo(
    () =>
      new Live(() => {
        sessionStorage.setItem(RENEWED, "");
        location.reload();
      }),
    [],
  );

  useEffect(() => {
    live.open();
    return () => live.close();
  }, [live]);

  const snapshot = useSyncExternalStore(live.subscribe, live.getSnapshot);
  return { live, ...snapshot };
}
