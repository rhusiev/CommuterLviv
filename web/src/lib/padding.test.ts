import { describe, expect, test } from "vitest";
import { FIT_PAD_PX, fitPadding } from "./padding";

const DESKTOP = { left: 0, top: 0, right: 1280, bottom: 720 };
const PHONE = { left: 0, top: 0, right: 393, bottom: 852 };

describe("fitPadding", () => {
  test("with no panel over it the map frames to its own edges", () => {
    expect(fitPadding(DESKTOP, null)).toEqual({
      top: FIT_PAD_PX,
      right: FIT_PAD_PX,
      bottom: FIT_PAD_PX,
      left: FIT_PAD_PX,
    });
  });

  test("a panel down the right frames to its left", () => {
    const panel = { left: 872, top: 76, right: 1268, bottom: 640 };

    expect(fitPadding(DESKTOP, panel)).toEqual({
      top: FIT_PAD_PX,
      right: 1280 - 872 + FIT_PAD_PX,
      bottom: FIT_PAD_PX,
      left: FIT_PAD_PX,
    });
  });

  test("a panel across the top of a phone frames below it", () => {
    const panel = { left: 12, top: 76, right: 381, bottom: 400 };

    expect(fitPadding(PHONE, panel).top).toBe(400 + FIT_PAD_PX);
  });

  test("a panel leaving no strip wide enough is framed under", () => {
    const panel = { left: 12, top: 76, right: 381, bottom: 772 };

    expect(fitPadding(PHONE, panel)).toEqual(fitPadding(PHONE, null));
  });

  test("a hidden panel covers nothing", () => {
    const panel = { left: 0, top: 0, right: 0, bottom: 0 };

    expect(fitPadding(DESKTOP, panel)).toEqual(fitPadding(DESKTOP, null));
  });
});
