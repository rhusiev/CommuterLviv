import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

type Position = typeof import("./position");

const PERMISSION_DENIED = 1;
const TIMEOUT = 3;
const ASK_MS = 10_000;
const ASK = { enableHighAccuracy: true, timeout: ASK_MS };

const fix = (latitude: number) =>
  ({ coords: { latitude, longitude: 24, accuracy: 5 }, timestamp: latitude }) as unknown as GeolocationPosition;
const error = (code: number) =>
  ({ code, PERMISSION_DENIED, POSITION_UNAVAILABLE: 2, TIMEOUT, message: "" }) as GeolocationPositionError;

/** A browser's geolocation that answers only when told to */
function browser() {
  const watches = new Map<number, { ok: PositionCallback; fail: PositionErrorCallback }>();
  let next = 0;
  return {
    watches,
    watchPosition: vi.fn((ok: PositionCallback, fail: PositionErrorCallback) => {
      watches.set(++next, { ok, fail });
      return next;
    }),
    clearWatch: vi.fn((id: number) => watches.delete(id)),
    getCurrentPosition: vi.fn(),
    move: (pos: GeolocationPosition) => watches.forEach((w) => w.ok(pos)),
    refuse: () => watches.forEach((w) => w.fail(error(PERMISSION_DENIED))),
  };
}

let geo: ReturnType<typeof browser>;
let position: Position;

beforeEach(async () => {
  geo = browser();
  vi.stubGlobal("navigator", { geolocation: geo });
  vi.resetModules();
  position = await import("./position");
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe("the position watched", () => {
  test("is watched once, and a later watcher is handed the last fix at once", async () => {
    const first = vi.fn();
    const later = vi.fn();
    position.watchHere(first, vi.fn());
    geo.move(fix(1));

    position.watchHere(later, vi.fn());
    await Promise.resolve();

    expect(geo.watchPosition).toHaveBeenCalledTimes(1);
    expect(later).toHaveBeenCalledWith(fix(1));
  });

  test("is let go only when the last watcher leaves", () => {
    const one = position.watchHere(vi.fn(), vi.fn());
    const two = position.watchHere(vi.fn(), vi.fn());

    one();
    expect(geo.clearWatch).not.toHaveBeenCalled();
    two();
    expect(geo.clearWatch).toHaveBeenCalledTimes(1);
  });

  test("once refused, is asked for again by the next watcher", () => {
    const fail = vi.fn();
    position.watchHere(vi.fn(), fail);

    geo.refuse();
    position.watchHere(vi.fn(), vi.fn());

    expect(fail).toHaveBeenCalledWith(error(PERMISSION_DENIED));
    expect(geo.watchPosition).toHaveBeenCalledTimes(2);
  });
});

describe("one fix", () => {
  test("is asked of the browser when nothing watches", () => {
    void position.hereOnce(ASK);

    expect(geo.getCurrentPosition).toHaveBeenCalledWith(expect.any(Function), expect.any(Function), ASK);
  });

  test("is the watch's last one while it watches, the browser not asked", async () => {
    position.watchHere(vi.fn(), vi.fn());
    geo.move(fix(1));

    await expect(position.hereOnce(ASK)).resolves.toEqual(fix(1));
    expect(geo.getCurrentPosition).not.toHaveBeenCalled();
  });

  test("waits for the watch's first, and leaves it once had", async () => {
    const leave = position.watchHere(vi.fn(), vi.fn());
    const got = position.hereOnce(ASK);

    geo.move(fix(2));
    leave();

    await expect(got).resolves.toEqual(fix(2));
    expect(geo.clearWatch).toHaveBeenCalledTimes(1);
  });

  test("is given up when the watch has none in time", async () => {
    vi.useFakeTimers();
    position.watchHere(vi.fn(), vi.fn());
    const got = position.hereOnce(ASK);

    vi.advanceTimersByTime(ASK_MS);

    await expect(got).rejects.toBe("none");
  });

  test("is refused when the watch is", async () => {
    position.watchHere(vi.fn(), vi.fn());
    const got = position.hereOnce(ASK);

    geo.refuse();

    await expect(got).rejects.toBe("refused");
  });
});
