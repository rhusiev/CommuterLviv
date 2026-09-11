import { useState } from "react";
import { api } from "../lib/api";
import { t } from "../lib/i18n";
import { RouteBadge } from "./RouteBadge";
import type { Catalog, Journey, Leg, Place } from "../lib/types";

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

/** Close enough to be the same doorway: a ten-thousandth of a degree is about
 * 11 m, which is narrower than any place worth naming */
const same = (a: Point, b: Place) =>
  Math.abs(a.lat - b.lat) < 1e-4 && Math.abs(a.lon - b.lon) < 1e-4;

export function JourneyPanel({
  catalog,
  from,
  to,
  picking,
  onPick,
  onSwap,
  onHere,
  onStop,
  onPoint,
  onLine,
  places,
  onPlaces,
}: {
  catalog: Catalog;
  from: Point | null;
  to: Point | null;
  picking: "from" | "to" | null;
  onPick: (which: "from" | "to" | null) => void;
  onSwap: () => void;
  onHere: (which: "from" | "to") => void;
  onStop: (i: number) => void;
  /** An end was given a point directly, from a saved place */
  onPoint: (which: "from" | "to", at: Point) => void;
  /** A route's line, from the badge on a ride */
  onLine: (i: number) => void;
  places: Place[];
  onPlaces: (next: Place[]) => void;
}) {
  const [options, setOptions] = useState<Journey[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState<string | null>(null);

  /** Kept by name, so saving over a name moves that place rather than making a
   * second one with the same label */
  const save = (at: Point) => {
    const name = window.prompt(t.namePlace)?.trim();
    if (!name) return;
    onPlaces([...places.filter((p) => p.name !== name), { name, lat: at.lat, lon: at.lon }]);
  };

  const forget = (place: Place) => onPlaces(places.filter((p) => p.name !== place.name));

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
        places={places}
        onPlace={(p) => onPoint("from", p)}
        onSave={from && (() => save(from))}
        onForget={forget}
      />
      <Field
        label={t.to}
        point={to}
        picking={picking === "to"}
        onPick={() => onPick(picking === "to" ? null : "to")}
        onHere={() => onHere("to")}
        places={places}
        onPlace={(p) => onPoint("to", p)}
        onSave={to && (() => save(to))}
        onForget={forget}
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
        <Option key={i} journey={j} catalog={catalog} onStop={onStop} onLine={onLine} />
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
  places,
  onPlace,
  onSave,
  onForget,
}: {
  label: string;
  point: Point | null;
  picking: boolean;
  onPick: () => void;
  onHere: () => void;
  places: Place[];
  onPlace: (at: Point) => void;
  /** Null until this end has a point: there is nothing to save yet */
  onSave: (() => void) | null;
  onForget: (place: Place) => void;
}) {
  const [open, setOpen] = useState(false);
  const saved = point && places.find((p) => same(point, p));
  return (
    <div className="relative flex items-center gap-2">
      <span className="w-12 shrink-0 text-xs uppercase tracking-wide text-slate-500">{label}</span>
      <button
        onClick={onPick}
        className={`min-w-0 flex-1 truncate rounded-md px-2 py-1.5 text-left text-sm ${
          picking ? "bg-accent/25 text-accent" : "bg-raised/70 hover:bg-raised"
        }`}
      >
        {saved ? saved.name : point ? `${point.lat.toFixed(4)}, ${point.lon.toFixed(4)}` : t.tapMap}
      </button>
      <button
        onClick={onHere}
        className="btn-quiet shrink-0 px-2 text-xs"
      >
        {t.useHere}
      </button>
      <button
        onClick={() => setOpen(!open)}
        title={t.places}
        className={`btn-quiet shrink-0 px-2 text-xs ${saved ? "text-accent" : ""}`}
      >
        {saved ? "★" : "☆"}
      </button>
      {open && (
        <div className="panel absolute right-0 top-full z-30 mt-1 w-56 p-1 text-sm">
          {places.length === 0 && <p className="px-2 py-1 text-xs text-slate-500">{t.noPlaces}</p>}
          {places.map((p) => (
            <div key={p.name} className="flex items-center gap-1">
              <button
                onClick={() => {
                  onPlace(p);
                  setOpen(false);
                }}
                className="min-w-0 flex-1 truncate rounded-md px-2 py-1 text-left hover:bg-raised"
              >
                {p.name}
              </button>
              <button
                onClick={() => onForget(p)}
                className="px-2 text-xs text-slate-500 hover:text-rose-300"
              >
                {t.forget}
              </button>
            </div>
          ))}
          {onSave && !saved && (
            <button
              onClick={() => {
                onSave();
                setOpen(false);
              }}
              className="mt-1 w-full rounded-md px-2 py-1 text-left text-accent hover:bg-raised"
            >
              {t.savePlace}
            </button>
          )}
        </div>
      )}
    </div>
  );
}

function Option({
  journey,
  catalog,
  onStop,
  onLine,
}: {
  journey: Journey;
  catalog: Catalog;
  onStop: (i: number) => void;
  onLine: (i: number) => void;
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
              <Ride leg={leg} catalog={catalog} onStop={onStop} onLine={onLine} />
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
  onLine,
}: {
  leg: Leg;
  catalog: Catalog;
  onStop: (i: number) => void;
  onLine: (i: number) => void;
}) {
  const route = leg.route === undefined ? undefined : catalog.routes[leg.route];
  return (
    <>
      <span className="w-14 shrink-0 text-xs tabular-nums text-slate-400">{clock(leg.dep)}</span>
      {route && (
        <button onClick={() => onLine(leg.route!)} title={t.showLine} className="shrink-0">
          <RouteBadge route={route} className="px-1.5 text-xs" />
        </button>
      )}
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
