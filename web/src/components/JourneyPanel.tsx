import { useState } from "react";
import { api } from "../lib/api";
import { t } from "../lib/i18n";
import { RouteBadge } from "./RouteBadge";
import type { Catalog, Journey, Leg } from "../lib/types";

/** Door to door: two points, and the ways between them.
 *
 * The points are set by tapping the map, which is the one gesture that needs
 * no address database - this service has stop names and nothing else, and a
 * planner that could only start from a stop would answer a question nobody
 * asked.
 *
 * Each ride says whether it came from a tracked vehicle or from the timetable.
 * That is not decoration: past three quarters of an hour the model has nothing
 * to say and the leg is the schedule's guess, and a rider deciding whether to
 * run for a bus deserves to know which of the two they are reading.
 */

export type Point = { lat: number; lon: number };

const clock = (t: number) =>
  new Date(t * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

const mins = (s: number) => Math.max(1, Math.round(s / 60));

export function JourneyPanel({
  catalog,
  from,
  to,
  picking,
  onPick,
  onSwap,
  onHere,
  onStop,
}: {
  catalog: Catalog;
  from: Point | null;
  to: Point | null;
  picking: "from" | "to" | null;
  onPick: (which: "from" | "to" | null) => void;
  onSwap: () => void;
  onHere: (which: "from" | "to") => void;
  onStop: (i: number) => void;
}) {
  const [options, setOptions] = useState<Journey[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState<string | null>(null);

  const search = async () => {
    if (!from || !to) return;
    setBusy(true);
    setFailed(null);
    try {
      const got = await api.plan([from.lat, from.lon], [to.lat, to.lon]);
      setOptions(got.options);
    } catch (err) {
      setFailed(err instanceof Error ? err.message : t.failed);
      setOptions(null);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="flex h-full flex-col gap-2 overflow-y-auto">
      <Field
        label={t.from}
        point={from}
        picking={picking === "from"}
        onPick={() => onPick(picking === "from" ? null : "from")}
        onHere={() => onHere("from")}
      />
      <Field
        label={t.to}
        point={to}
        picking={picking === "to"}
        onPick={() => onPick(picking === "to" ? null : "to")}
        onHere={() => onHere("to")}
      />

      <div className="flex gap-2">
        <button
          onClick={() => void search()}
          disabled={!from || !to || busy}
          className="btn flex-1 disabled:bg-raised/70 disabled:text-slate-500"
        >
          {busy ? t.searching : t.findRoute}
        </button>
        <button
          onClick={onSwap}
          className="btn-quiet"
        >
          {t.swap}
        </button>
      </div>

      {failed !== null && <p className="text-sm text-rose-300">{failed}</p>}
      {options === null && failed === null && (
        <p className="text-sm text-slate-500">{t.planHint}</p>
      )}
      {options !== null && options.length === 0 && (
        <p className="text-sm text-slate-500">{t.noJourney}</p>
      )}

      {options?.map((j, i) => (
        <Option key={i} journey={j} catalog={catalog} onStop={onStop} />
      ))}
    </div>
  );
}

function Field({
  label,
  point,
  picking,
  onPick,
  onHere,
}: {
  label: string;
  point: Point | null;
  picking: boolean;
  onPick: () => void;
  onHere: () => void;
}) {
  return (
    <div className="flex items-center gap-2">
      <span className="w-12 shrink-0 text-xs uppercase tracking-wide text-slate-500">{label}</span>
      <button
        onClick={onPick}
        className={`min-w-0 flex-1 truncate rounded-md px-2 py-1.5 text-left text-sm ${
          picking ? "bg-accent/25 text-accent" : "bg-raised/70 hover:bg-raised"
        }`}
      >
        {point ? `${point.lat.toFixed(4)}, ${point.lon.toFixed(4)}` : t.tapMap}
      </button>
      <button
        onClick={onHere}
        className="btn-quiet shrink-0 px-2 text-xs"
      >
        {t.useHere}
      </button>
    </div>
  );
}

function Option({
  journey,
  catalog,
  onStop,
}: {
  journey: Journey;
  catalog: Catalog;
  onStop: (i: number) => void;
}) {
  const changes = Math.max(0, journey.rides - 1);
  return (
    <div className="inset-panel p-2">
      <div className="flex items-baseline gap-2">
        <span className="font-medium text-slate-100">
          {t.minutes(mins(journey.arr - journey.dep))}
        </span>
        <span className="text-xs text-slate-400">
          {clock(journey.dep)} - {clock(journey.arr)}
        </span>
        <span className="ml-auto text-xs text-slate-500">
          {journey.rides === 0
            ? t.wholeWalk
            : changes === 0
              ? t.noChange
              : t.changeCount(changes)}
        </span>
      </div>
      <ol className="mt-1.5 space-y-1">
        {journey.legs.map((leg, i) => (
          <li key={i} className="flex items-baseline gap-2 text-sm">
            {leg.kind === "walk" ? (
              <>
                <span className="w-14 shrink-0 text-xs text-slate-500">
                  {t.walkLeg(mins(leg.arr - leg.dep))}
                </span>
                <span className="min-w-0 flex-1 truncate text-slate-400">
                  {leg.b < 0 ? t.toDoor : (catalog.stops[leg.b]?.name ?? "")}
                </span>
              </>
            ) : (
              <Ride leg={leg} catalog={catalog} onStop={onStop} />
            )}
          </li>
        ))}
      </ol>
    </div>
  );
}

function Ride({
  leg,
  catalog,
  onStop,
}: {
  leg: Leg;
  catalog: Catalog;
  onStop: (i: number) => void;
}) {
  const route = leg.route === undefined ? undefined : catalog.routes[leg.route];
  return (
    <>
      <span className="w-14 shrink-0 text-xs tabular-nums text-slate-400">{clock(leg.dep)}</span>
      {route && <RouteBadge route={route} className="shrink-0 px-1.5 text-xs" />}
      <button
        onClick={() => leg.b >= 0 && onStop(leg.b)}
        className="min-w-0 flex-1 truncate text-left text-slate-200 hover:underline"
      >
        {catalog.stops[leg.b]?.name ?? ""}
      </button>
      <span className={`shrink-0 text-xs ${leg.live ? "text-emerald-400" : "text-slate-500"}`}>
        {leg.live ? t.livePart : t.schedulePart}
      </span>
    </>
  );
}
