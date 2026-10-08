import { useState } from "react";
import { canKeepAwake, heldAwake, holdAwake, useAwake } from "../lib/awake";
import { clock, countdown } from "../lib/eta";
import type { Progress, Stage } from "../lib/follow";
import { t } from "../lib/i18n";
import { current, rows, type Row } from "../lib/legs";
import type { Live } from "../lib/live";
import type { Arrival, Catalog, Journey } from "../lib/types";
import { Icon } from "./Icon";
import { RouteBadge } from "./RouteBadge";

/** What to do now on a journey being followed; a tap on it lists every step */
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
  const [awake, setAwake] = useState(heldAwake);
  const [steps, setSteps] = useState(false);
  useAwake(awake && !done);
  return (
    <div className="panel pointer-events-auto p-3">
      <div className="flex items-start gap-2">
        {/* A div, as a button may not hold the paragraphs of the step */}
        <div
          role="button"
          tabIndex={0}
          onClick={() => setSteps(!steps)}
          onKeyDown={(e) => {
            if (e.key !== "Enter" && e.key !== " ") return;
            e.preventDefault();
            setSteps(!steps);
          }}
          aria-expanded={steps}
          title={steps ? t.hideSteps : t.showSteps}
          className="flex min-w-0 flex-1 cursor-pointer items-start gap-1 text-sm"
        >
          <div className="min-w-0 flex-1">
            {progress === null ? (
              <p className="text-slate-400">{t.locating}</p>
            ) : progress === "denied" ? (
              <p className="text-rose-300">{t.noLocation}</p>
            ) : (
              <Step catalog={catalog} journey={journey} live={live} progress={progress} />
            )}
          </div>
          <Icon name={steps ? "up" : "down"} className="size-4 shrink-0 text-slate-500" />
        </div>
        {canKeepAwake() && !done && (
          <button
            onClick={() => {
              holdAwake(!awake);
              setAwake(!awake);
            }}
            aria-pressed={awake}
            title={t.keepAwakeHint}
            className={awake ? "btn" : "btn-quiet"}
          >
            {t.keepAwake}
          </button>
        )}
        <button onClick={onEnd} className={done ? "btn" : "btn-quiet"}>
          {done ? t.ok : t.endFollow}
        </button>
      </div>
      {steps && (
        <Steps
          catalog={catalog}
          journey={journey}
          stage={progress !== null && progress !== "denied" ? progress.stage : null}
        />
      )}
    </div>
  );
}

/** Every walk, wait and ride of the journey with when it starts and ends, the
 *  one under way marked */
function Steps({
  catalog,
  journey,
  stage,
}: {
  catalog: Catalog;
  journey: Journey;
  /** Where the journey is, or null while that is not known */
  stage: Stage | null;
}) {
  const list = rows(journey);
  const now = stage === null ? -1 : current(list, stage);
  return (
    <ol className="mt-2 max-h-64 space-y-0.5 overflow-y-auto border-t border-raised pt-2">
      {list.map((row, i) => (
        <li
          key={i}
          aria-current={i === now ? "step" : undefined}
          className={`flex items-center gap-2 rounded-md px-1 py-0.5 text-sm ${
            i === now ? "bg-raised text-slate-100" : i < now ? "text-slate-500" : "text-slate-300"
          }`}
        >
          <span className="w-24 shrink-0 text-xs tabular-nums text-slate-400">
            {clock(row.dep)} - {clock(row.arr)}
          </span>
          <StepRow catalog={catalog} row={row} />
        </li>
      ))}
    </ol>
  );
}

function StepRow({ catalog, row }: { catalog: Catalog; row: Row }) {
  const name = (i: number) => stopName(catalog, i);
  if (row.kind === "ride") {
    const route = row.route === undefined ? undefined : catalog.routes[row.route];
    return (
      <>
        {route && <RouteBadge route={route} className="shrink-0 px-1.5 text-xs" />}
        <span className="min-w-0 truncate">
          {name(row.a)} → {name(row.b)}
        </span>
      </>
    );
  }
  const [icon, text] =
    row.kind === "wait"
      ? (["clock", t.waitAt(name(row.at))] as const)
      : (["walk", row.to < 0 ? t.walkHome : row.change ? t.changeAt(name(row.to)) : t.walkTo(name(row.to))] as const);
  return (
    <>
      <Icon name={icon} className="size-4 shrink-0 text-slate-500" />
      <span className="min-w-0 truncate">{text}</span>
    </>
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
  const name = (i: number) => stopName(catalog, i);
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
    head = progress.soon ? t.offSoon(name(leg.b)) : t.offAt(name(leg.b));
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

const stopName = (catalog: Catalog, i: number) => catalog.stops[i]?.name ?? "";
