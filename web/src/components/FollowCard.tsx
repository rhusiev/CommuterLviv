import { countdown } from "../lib/eta";
import type { Progress } from "../lib/follow";
import { t } from "../lib/i18n";
import type { Live } from "../lib/live";
import type { Arrival, Catalog, Journey } from "../lib/types";
import { RouteBadge } from "./RouteBadge";

/** Closer than this to the stop to get off at, the card says to get ready.
 * Chosen, not derived: about a stop's spacing in the city centre. */
const SOON_M = 400;

/** What to do now on a journey being followed */
export function FollowCard({
  catalog,
  journey,
  live,
  progress,
  onEnd,
}: {
  catalog: Catalog;
  journey: Journey;
  live: Live;
  progress: Progress | "denied" | null;
  onEnd: () => void;
}) {
  const done = progress !== null && progress !== "denied" && progress.stage.kind === "arrived";
  return (
    <div className="panel pointer-events-auto flex items-start gap-2 p-3">
      <div className="min-w-0 flex-1 text-sm">
        {progress === null ? (
          <p className="text-slate-400">{t.locating}</p>
        ) : progress === "denied" ? (
          <p className="text-rose-300">{t.noLocation}</p>
        ) : (
          <Step catalog={catalog} journey={journey} live={live} progress={progress} />
        )}
      </div>
      <button onClick={onEnd} className={done ? "btn" : "btn-quiet"}>
        {done ? t.ok : t.endFollow}
      </button>
    </div>
  );
}

function Step({
  catalog,
  journey,
  live,
  progress,
}: {
  catalog: Catalog;
  journey: Journey;
  live: Live;
  progress: Progress;
}) {
  const { stage } = progress;
  if (stage.kind === "arrived") return <p className="font-medium text-slate-100">{t.arrived}</p>;
  const leg = journey.legs[stage.leg]!;
  const route = leg.route === undefined ? undefined : catalog.routes[leg.route];
  const name = (i: number) => catalog.stops[i]?.name ?? "";
  const due = (stop: number) =>
    live.arrivals[String(stop)]?.filter((a) => a.route === leg.route) ?? [];
  let head: string;
  let when: Arrival | undefined;
  if (stage.kind === "walk") {
    head = leg.b < 0 ? t.walkHome : t.walkTo(name(leg.b));
  } else if (stage.kind === "wait") {
    // The planned vehicle, or the route's next one when it is not coming
    const at = due(leg.a);
    head = t.waitAt(name(leg.a));
    when = at.find((a) => a.veh === leg.veh) ?? at[0];
  } else {
    // Only the vehicle ridden says when it gets there; another of its route
    // could be the one ahead
    head = progress.left <= SOON_M ? t.offSoon(name(leg.b)) : t.offAt(name(leg.b));
    when = stage.veh === null ? undefined : due(leg.b).find((a) => a.veh === stage.veh);
  }
  return (
    <>
      <p className="flex items-baseline gap-2">
        {stage.kind !== "walk" && route && (
          <RouteBadge route={route} className="shrink-0 px-1.5 text-xs" />
        )}
        <span className="min-w-0 truncate font-medium text-slate-100">{head}</span>
      </p>
      <p className="mt-0.5 text-xs text-slate-400">
        {stage.kind === "wait" ? (when ? t.dueIn(countdown(when.t)) : "") : t.toGo(distance(progress.left))}
        {stage.kind === "ride" && when && ` · ${countdown(when.t)}`}
      </p>
      {progress.passed && <p className="mt-1 text-xs text-rose-300">{t.passedStop}</p>}
      {!progress.passed && progress.astray && (
        <p className="mt-1 text-xs text-amber-300">{t.offTheWay}</p>
      )}
    </>
  );
}

const M_PER_KM = 1000;
/** Short distances are said to this many metres */
const STEP_M = 10;

function distance(m: number): string {
  return m < M_PER_KM ? t.metres(Math.round(m / STEP_M) * STEP_M) : t.km(m / M_PER_KM);
}
