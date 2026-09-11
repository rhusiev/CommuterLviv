import { colour, number } from "../lib/sprites";
import type { Route } from "../lib/types";

export function ModeIcon({ type, className = "size-4" }: { type: string; className?: string }) {
  const tram = type === "tram";
  return (
    // A tram is the narrower body under a wire; a trolleybus is the bus with
    // the poles it draws its power through
    <svg
      viewBox="0 0 24 24"
      className={className}
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      aria-hidden
    >
      <rect x={tram ? 6.5 : 4.5} y="4.5" width={tram ? 11 : 15} height="13" rx="3" />
      <path d={tram ? "M6.5 11h11" : "M4.5 11h15"} />
      <path d={tram ? "M9 17.5v2.5M15 17.5v2.5" : "M8 17.5v2.5M16 17.5v2.5"} />
      {tram && <path d="M12 4.5V2M8 2h8" />}
      {type === "trolleybus" && <path d="M14 4.5 18.5 1M11 4.5 15.5 1" />}
    </svg>
  );
}

export function RouteBadge({
  route,
  className = "",
  muted = false,
}: {
  route: Route;
  className?: string;
  /** The shape without the route's colour */
  muted?: boolean;
}) {
  return (
    <span
      className={`inline-flex items-center justify-center gap-1 rounded font-semibold ${className}`}
      style={muted ? undefined : { backgroundColor: colour(route.short, route.type), color: "#0b0f14" }}
      title={route.long}
    >
      <ModeIcon type={route.type} />
      {/* A floor of two digits, so a wall of chips lines up */}
      <span className="min-w-[2.5ch] text-center tabular-nums">{number(route.short)}</span>
    </span>
  );
}
