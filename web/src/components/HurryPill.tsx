import type { ReactNode } from "react";
import { Icon } from "./Icon";

const PILL =
  "inline-flex shrink-0 items-center gap-1 rounded-full bg-amber-400/15 px-2 py-0.5 text-xs font-medium whitespace-nowrap text-amber-300 ring-1 ring-amber-400/50";

/** Hurrying asked for, in amber with a runner. With `onWhy` it is a button
 *  marked ⓘ that asks for `hint` to be said, where its caller has room for it;
 *  without, as on a card that is one click target, it only shows */
export function HurryPill({
  hint,
  onWhy,
  children,
}: {
  hint: string;
  onWhy?: () => void;
  children: ReactNode;
}) {
  if (!onWhy)
    return (
      <span className={PILL}>
        <Icon name="run" className="size-3.5" />
        {children}
      </span>
    );
  return (
    <button
      onClick={(e) => {
        // It sits on cards that take a click of their own
        e.stopPropagation();
        onWhy();
      }}
      title={hint}
      className={PILL}
    >
      <Icon name="run" className="size-3.5" />
      {children}
      <Icon name="info" className="size-3.5" />
    </button>
  );
}
