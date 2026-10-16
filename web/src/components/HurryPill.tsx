import type { ReactNode } from "react";
import { Icon } from "./Icon";

/** Hurrying asked for, in amber with a runner, `hint` on hover */
export function HurryPill({ hint, children }: { hint: string; children: ReactNode }) {
  return (
    <span
      title={hint}
      className="inline-flex shrink-0 items-center gap-1 rounded-full bg-amber-400/15 px-2 py-0.5 text-xs font-medium whitespace-nowrap text-amber-300 ring-1 ring-amber-400/50"
    >
      <Icon name="run" className="size-3.5" />
      {children}
    </span>
  );
}
