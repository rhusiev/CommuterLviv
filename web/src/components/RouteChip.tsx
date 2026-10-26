import type { ReactNode } from "react";
import { t } from "../lib/i18n";
import type { Route } from "../lib/types";
import { RouteBadge } from "./RouteBadge";

/** A route, the same chip wherever one is shown: its body watches the route on
 * the map or stops watching it, and the `›` beside it opens the route's line.
 * Both are drawn as targets, so nothing hides behind a long press. */
export function RouteChip({
  route,
  watched,
  onWatch,
  onLine,
  children,
  className = "",
}: {
  route: Route;
  watched: boolean;
  onWatch: () => void;
  onLine: () => void;
  /** Said in the body after the badge, such as a countdown */
  children?: ReactNode;
  className?: string;
}) {
  return (
    <span
      className={`inline-flex items-stretch overflow-hidden rounded-control bg-raised/70 text-sm ${className}`}
    >
      <button
        onClick={onWatch}
        aria-pressed={watched}
        title={watched ? t.unwatchRoute : t.watchRoute}
        className="flex min-w-0 flex-1 items-center gap-1.5 py-1 pl-1 pr-1.5 hover:bg-raised"
      >
        <RouteBadge
          route={route}
          muted={!watched}
          className={`px-1.5 py-0.5 ${watched ? "" : "text-slate-400"}`}
        />
        {children}
      </button>
      <button
        onClick={onLine}
        aria-label={t.lineOf(route.short)}
        title={t.showLine}
        className="border-l border-hair px-2 text-slate-400 hover:bg-raised hover:text-slate-100"
      >
        ›
      </button>
    </span>
  );
}
