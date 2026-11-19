/** Whether a followed journey is searched again as it goes, so the way and its
 *  times keep up with delays. Off until asked: with it on, the fix leaves the
 *  device while following, which the app otherwise does not do. */
const key = "commuterlviv.refresh";

export function heldRefresh(): boolean {
  return localStorage.getItem(key) === "1";
}

export function holdRefresh(on: boolean) {
  if (on) localStorage.setItem(key, "1");
  else localStorage.removeItem(key);
}

/** Seconds between two searches while a journey is followed. Chosen, not
 *  derived: often enough to catch a delay, rare enough to cost little */
export const REFRESH_EVERY_S = 30;

/** How long the card says the route was updated */
export const UPDATED_SAID_MS = 15_000;
