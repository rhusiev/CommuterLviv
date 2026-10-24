import { afterEach, beforeEach, describe, expect, test, vi, type Mock } from "vitest";
import { Hold, HOLD_MS, HOLD_SLOP_PX, type Touched } from "./hold";

const finger = (clientX: number, clientY = 0) => ({ clientX, clientY });

describe("Hold", () => {
  let onHold: Mock<(at: Touched) => void>;
  let hold: Hold;

  beforeEach(() => {
    vi.useFakeTimers();
    onHold = vi.fn();
    hold = new Hold(onHold);
  });
  afterEach(() => vi.useRealTimers());

  test("a finger resting long enough is a hold where it went down", () => {
    hold.start([finger(100, 50)]);
    vi.advanceTimersByTime(HOLD_MS - 1);
    expect(onHold).not.toHaveBeenCalled();
    hold.move([finger(100 + HOLD_SLOP_PX, 50)]);
    vi.advanceTimersByTime(1);
    expect(onHold).toHaveBeenCalledExactlyOnceWith(finger(100, 50));
    expect(hold.end()).toBe(true);
  });

  test("a tap is no hold, and its end is let through", () => {
    hold.start([finger(0)]);
    vi.advanceTimersByTime(HOLD_MS / 2);
    expect(hold.end()).toBe(false);
    vi.advanceTimersByTime(HOLD_MS);
    expect(onHold).not.toHaveBeenCalled();
  });

  test("a finger moving further than the slop, a second finger or the map moving cancels it", () => {
    hold.start([finger(0)]);
    hold.move([finger(HOLD_SLOP_PX + 1)]);
    hold.start([finger(0), finger(50)]);
    hold.start([finger(0)]);
    hold.move([finger(0), finger(50)]);
    hold.start([finger(0)]);
    hold.cancel();
    vi.advanceTimersByTime(HOLD_MS);
    expect(onHold).not.toHaveBeenCalled();
  });

  test("a contextmenu before the hold answers the press alone", () => {
    hold.start([finger(0)]);
    vi.advanceTimersByTime(HOLD_MS / 2);
    expect(hold.menu()).toBe(false);
    vi.advanceTimersByTime(HOLD_MS);
    expect(onHold).not.toHaveBeenCalled();
  });

  test("a contextmenu after the hold is swallowed once, and a right click later is not", () => {
    hold.start([finger(0)]);
    vi.advanceTimersByTime(HOLD_MS);
    expect(onHold).toHaveBeenCalledOnce();
    expect(hold.menu()).toBe(true);
    expect(hold.menu()).toBe(false);
  });

  test("the next press starts afresh", () => {
    hold.start([finger(0)]);
    vi.advanceTimersByTime(HOLD_MS);
    hold.end();
    hold.start([finger(0)]);
    expect(hold.end()).toBe(false);
  });
});
