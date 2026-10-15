/** One watch on the device's position for the whole page. A browser already
 * watching may not answer a second watch, or a single ask, until the position
 * moves - so a device standing still would never be found by the second one.
 * Whoever comes later is handed the last fix instead. */

/** Why no fix came: the browser was refused it, or it did not come in time */
export type NoFix = "refused" | "none";

type Watcher = { fix: PositionCallback; fail: PositionErrorCallback };

// Each fix a fresh one: the follower tells boarding from how fast they move
const OPTIONS: PositionOptions = { enableHighAccuracy: true, maximumAge: 0 };

const watchers = new Set<Watcher>();
let watch: number | null = null;
let last: GeolocationPosition | null = null;

function start() {
  watch = navigator.geolocation.watchPosition(
    (pos) => {
      last = pos;
      for (const w of [...watchers]) w.fix(pos);
    },
    (err) => {
      // A refused watch says nothing more, so the next watcher asks again
      if (err.code === err.PERMISSION_DENIED) stop();
      for (const w of [...watchers]) w.fail(err);
    },
    OPTIONS,
  );
}

function stop() {
  if (watch !== null) navigator.geolocation.clearWatch(watch);
  watch = null;
  last = null;
}

/** Calls `fix` with each fix, the last one first if there is one already, and
 * `fail` with each error, until the function it returns is called */
export function watchHere(fix: PositionCallback, fail: PositionErrorCallback): () => void {
  const watcher = { fix, fail };
  watchers.add(watcher);
  if (watch === null) {
    start();
  } else if (last) {
    const held = last;
    queueMicrotask(() => {
      if (watchers.has(watcher)) fix(held);
    });
  }
  return () => {
    watchers.delete(watcher);
    if (watchers.size === 0) stop();
  };
}

/** One fix: the last one, while the position is watched, else the browser is
 * asked with `options`. Rejects with a `NoFix` */
export function hereOnce(options: PositionOptions & { timeout: number }): Promise<GeolocationPosition> {
  return new Promise((ok, fail) => {
    const no = (err: GeolocationPositionError) =>
      fail((err.code === err.PERMISSION_DENIED ? "refused" : "none") satisfies NoFix);
    if (watch === null) {
      navigator.geolocation.getCurrentPosition(ok, no, options);
      return;
    }
    const timer = setTimeout(() => {
      leave();
      fail("none" satisfies NoFix);
    }, options.timeout);
    const leave = watchHere(
      (pos) => {
        clearTimeout(timer);
        leave();
        ok(pos);
      },
      (err) => {
        if (err.code !== err.PERMISSION_DENIED) return;
        clearTimeout(timer);
        leave();
        no(err);
      },
    );
  });
}
