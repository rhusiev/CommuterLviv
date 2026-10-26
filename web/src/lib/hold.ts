/** How long a finger rests on the map before it is a long press: iOS's own
 * default, `UILongPressGestureRecognizer.minimumPressDuration` */
export const HOLD_MS = 500;
/** How far it may wander meanwhile, in CSS pixels: iOS's `allowableMovement` */
export const HOLD_SLOP_PX = 10;

export type Touched = { clientX: number; clientY: number };

/** A long press told from the touches themselves. Android's browsers raise one
 * as `contextmenu`, iOS Safari raises nothing, so both are listened to and
 * whichever answers a press first answers it alone. */
export class Hold {
  private timer: ReturnType<typeof setTimeout> | undefined;
  private from: Touched | null = null;
  private held = false;

  constructor(private readonly onHold: (at: Touched) => void) {}

  /** Fingers went down; a second one is a pinch, not a hold */
  start(touches: ArrayLike<Touched>) {
    this.cancel();
    this.held = false;
    if (touches.length !== 1) return;
    const at = { clientX: touches[0]!.clientX, clientY: touches[0]!.clientY };
    this.from = at;
    this.timer = setTimeout(() => {
      this.cancel();
      this.held = true;
      this.onHold(at);
    }, HOLD_MS);
  }

  move(touches: ArrayLike<Touched>) {
    const from = this.from;
    if (!from) return;
    const to = touches[0];
    const strayed = !to || Math.hypot(to.clientX - from.clientX, to.clientY - from.clientY) > HOLD_SLOP_PX;
    if (touches.length !== 1 || strayed) this.cancel();
  }

  /** The finger lifted: true when the press was a hold, so the tap it would
   * also end as is not let through to whatever opened under it */
  end(): boolean {
    this.cancel();
    return this.held;
  }

  /** A `contextmenu` arrived: true when a hold already answered this press */
  menu(): boolean {
    this.cancel();
    const answered = this.held;
    this.held = false;
    return answered;
  }

  /** The press is no hold after all, as the map started to move */
  cancel() {
    clearTimeout(this.timer);
    this.timer = undefined;
    this.from = null;
  }
}

/** Feeds `hold` the touches on `el` */
export function listenForHold(el: HTMLElement, hold: Hold) {
  el.addEventListener("touchstart", (e) => hold.start(e.touches), { passive: true });
  el.addEventListener("touchmove", (e) => hold.move(e.touches), { passive: true });
  el.addEventListener("touchend", (e) => {
    if (hold.end()) e.preventDefault();
  });
  el.addEventListener("touchcancel", () => hold.cancel());
}
