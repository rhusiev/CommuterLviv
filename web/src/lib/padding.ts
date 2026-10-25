/** A rectangle on the page, as `getBoundingClientRect` gives it */
export type Box = { left: number; top: number; right: number; bottom: number };
export type Padding = { top: number; right: number; bottom: number; left: number };

/** Space kept between what the map frames and the map's edge */
export const FIT_PAD_PX = 48;
/** A strip beside a panel narrower than this, once padded, frames too little
 * to be worth it, and the panel is framed under instead. Chosen, not derived */
const MIN_FRAME_PX = 120;

/** The padding that frames clear of `panel` lying over `map`: in the largest
 * strip of the map the panel leaves free, or the map's own when no strip is
 * wide enough */
export function fitPadding(map: Box, panel: Box | null): Padding {
  const all = { top: FIT_PAD_PX, right: FIT_PAD_PX, bottom: FIT_PAD_PX, left: FIT_PAD_PX };
  if (!panel || panel.right <= panel.left || panel.bottom <= panel.top) return all;
  const width = map.right - map.left;
  const height = map.bottom - map.top;
  const strips: { free: number; across: number; side: keyof Padding; covered: number }[] = [
    { free: panel.left - map.left, across: height, side: "right", covered: map.right - panel.left },
    { free: map.right - panel.right, across: height, side: "left", covered: panel.right - map.left },
    { free: panel.top - map.top, across: width, side: "bottom", covered: map.bottom - panel.top },
    { free: map.bottom - panel.bottom, across: width, side: "top", covered: panel.bottom - map.top },
  ];
  const wide = strips.filter((s) => s.free - 2 * FIT_PAD_PX >= MIN_FRAME_PX);
  if (wide.length === 0) return all;
  const best = wide.reduce((a, b) => (b.free * b.across > a.free * a.across ? b : a));
  return { ...all, [best.side]: best.covered + FIT_PAD_PX };
}
