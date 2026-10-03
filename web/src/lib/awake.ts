import { useEffect } from "react";

/** A browser stops the fixes once the page is hidden, and nothing brings them
 *  back in the background. So the most the web can do for a followed journey
 *  is keep the screen from locking - asked for, as it costs battery */
const key = "commuterlviv.awake";

export const canKeepAwake = () => "wakeLock" in navigator;

export const heldAwake = () => localStorage.getItem(key) === "1";

export function holdAwake(on: boolean) {
  localStorage.setItem(key, on ? "1" : "0");
}

/** Keeps the screen on while `on`. The browser lets go of the lock whenever
 *  the page is hidden, so it is taken again each time the page comes back */
export function useAwake(on: boolean) {
  useEffect(() => {
    if (!on || !canKeepAwake()) return;
    let lock: WakeLockSentinel | null = null;
    let done = false;
    const take = () => {
      if (document.visibilityState !== "visible") return;
      navigator.wakeLock.request("screen").then(
        (l) => (done ? void l.release() : (lock = l)),
        // Refused, as on low battery: the screen locks as it would anyway
        () => {},
      );
    };
    take();
    document.addEventListener("visibilitychange", take);
    return () => {
      done = true;
      document.removeEventListener("visibilitychange", take);
      void lock?.release();
    };
  }, [on]);
}
