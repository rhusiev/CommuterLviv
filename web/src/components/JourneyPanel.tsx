import { useEffect, useRef, useState } from "react";
import { api, ApiError } from "../lib/api";
import { clock, mins } from "../lib/eta";
import { followable } from "../lib/follow";
import { t } from "../lib/i18n";
import { saved } from "../lib/places";
import {
  heldPrefer,
  holdPrefer,
  PREFERS,
  ranked,
  type Prefer,
} from "../lib/prefer";
import { heldSpeed } from "../lib/walking";
import { Backups, type WayPick } from "./Backups";
import { Icon, type IconName } from "./Icon";
import { RouteBadge } from "./RouteBadge";
import { Speed } from "./Speed";
import { StopSearch } from "./StopSearch";
import type { Aboard, Catalog, Confidence, Journey, Leg, Place } from "../lib/types";

export type Point = { lat: number; lon: number };
/** Where a journey starts: a point, or on board a vehicle */
export type Origin = Point | Aboard;

type End = "from" | "to";

/** What a ride not on a tracked vehicle rests on, how loudly to say so, and why
 *  it matters */
const RESTS: Record<
  Exclude<Confidence, "live">,
  { word: string; tone: string; why: string }
> = {
  schedule: {
    word: t.schedulePart,
    tone: "text-slate-500",
    why: t.scheduleWhy,
  },
  terminus: {
    word: t.terminusPart,
    tone: "text-slate-500",
    why: t.terminusWhy,
  },
  quiet: { word: t.quietPart, tone: "text-amber-400", why: t.quietWhy },
};

/** As far ahead as the server plans */
const AHEAD_S = 30 * 86400;

/** What `<input type="datetime-local">` wants: local wall clock, no zone */
const onClock = (at: number) => {
  const d = new Date(at * 1000);
  return new Date(d.getTime() - d.getTimezoneOffset() * 60_000).toISOString().slice(0, 16);
};

/** The same place: 1e-4 degrees is about 11 m */
const same = (a: Point, b: Place) =>
  Math.abs(a.lat - b.lat) < 1e-4 && Math.abs(a.lon - b.lon) < 1e-4;

const key = (p: Point) => `${p.lat},${p.lon}`;

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
  onShow,
  onFollow,
  folded,
  onFold,
}: {
  catalog: Catalog;
  from: Origin | null;
  to: Point | null;
  /** The end waiting on a click on the map; the panel folds out of its way */
  picking: End | null;
  onPick: (which: End | null) => void;
  onSwap: () => void;
  onHere: (which: End) => void;
  onStop: (i: number) => void;
  onPoint: (which: End, at: Point) => void;
  onLine: (i: number) => void;
  places: Place[];
  onPlaces: (next: Place[]) => void;
  /** The option picked to be drawn on the map, or null once none is */
  onShow: (j: Journey | null) => void;
  onFollow: (j: Journey) => void;
  /** Folded down to a strip, the map and the option on it in view */
  folded: boolean;
  onFold: (folded: boolean) => void;
}) {
  const [options, setOptions] = useState<Journey[] | null>(null);
  const [shown, setShown] = useState<Journey | null>(null);
  const show = (j: Journey | null) => {
    setShown(j);
    onShow(j);
  };
  // Leaving the planner takes its journey off the map
  useEffect(() => () => onShow(null), [onShow]);
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState<string | null>(null);
  /** The search's name for reporting it, until it is reported */
  const [report, setReport] = useState<string | null>(null);
  /** How reporting it went */
  const [reportSaid, setReportSaid] = useState<string | null>(null);
  /** The search's name for its backups, which reporting it leaves alone; the
   *  backups fetched as options of their own, by the option, leg and backup
   *  they came from; and the option of the search's each was built from */
  const held = useRef<{
    id: string | null;
    built: Map<string, Journey>;
    from: Map<Journey, number>;
  }>({ id: null, built: new Map(), from: new Map() });
  /** Unix seconds, or null for now - which is what the service assumes */
  const [at, setAt] = useState<number | null>(null);
  const [prefer, setPrefer] = useState<Prefer>(heldPrefer);
  /** km/h, starting at the one kept as the default */
  const [speed, setSpeed] = useState(heldSpeed);
  /** What the points picked by name were called, so they keep reading so */
  const names = useRef(new Map<string, string>());
  // Options found for other ends are not these ends' options
  useEffect(() => {
    setOptions(null);
    setFailed(null);
    setReport(null);
    setReportSaid(null);
    held.current = { id: null, built: new Map(), from: new Map() };
    setShown(null);
    onShow(null);
  }, [from, to, onShow]);
  const aboard = from && "veh" in from ? from : null;
  const start = from && !("veh" in from) ? from : null;

  const search = async () => {
    if (!from || !to) return;
    setBusy(true);
    setFailed(null);
    setReport(null);
    setReportSaid(null);
    show(null);
    try {
      // On board is now: the vehicle is tracked only as it goes
      const got = await api.plan(
        "veh" in from ? { veh: from.veh } : [from.lat, from.lon],
        [to.lat, to.lon],
        aboard ? null : at,
        speed,
      );
      setOptions(got.options);
      setReport(got.report ?? null);
      held.current = { id: got.report ?? null, built: new Map(), from: new Map() };
    } catch (err) {
      setFailed(
        err instanceof ApiError && err.preparing
          ? t.plannerPreparing
          : err instanceof Error
            ? err.message
            : t.failed,
      );
      setOptions(null);
    } finally {
      setBusy(false);
    }
  };

  const sendReport = async () => {
    const id = report;
    const note = prompt(t.reportNote);
    if (note === null || !id) return;
    try {
      await api.report(id, note);
      setReport((r) => (r === id ? null : r));
      setReportSaid(t.reported);
    } catch (err) {
      setReportSaid(err instanceof Error ? err.message : t.failed);
    }
  };

  /** Shows `j`, folding the panel out of the way of it on the map */
  const draw = (j: Journey) => {
    show(j);
    onFold(true);
  };
  /** Draws `pick` of option `j`: the journey itself, the option riding the
   *  same, or else that way fetched and listed as an option of its own */
  const takeWay = async (j: Journey, pick: WayPick) => {
    if (pick === null) return draw(j);
    const same = options?.[j.legs[pick.leg]?.backups?.[pick.n]?.option ?? -1];
    if (same) return draw(same);
    const search = held.current;
    const from = search.from.get(j) ?? options?.indexOf(j) ?? -1;
    const key = `${from} ${pick.leg} ${pick.n}`;
    let got = search.built.get(key);
    if (!got) {
      if (!search.id) throw new Error(t.searchAgain);
      got = await api.backup(search.id, from, pick.leg, pick.n);
      // a search made meanwhile has options of its own
      if (held.current !== search) return;
      search.built.set(key, got);
      search.from.set(got, from);
      setOptions((o) => o && [...o, got!]);
    }
    draw(got);
  };

  if (picking)
    return (
      <div className="flex items-center gap-2 text-sm">
        <Label text={END[picking].label} icon={END[picking].icon} />
        <span className="flex-1">
          {END[picking].label}: {t.tapMap}
        </span>
        <button onClick={() => onPick(null)} className="btn-quiet px-2">
          <Icon name="clear" className="size-4" />
        </button>
      </div>
    );

  if (folded)
    return (
      <button
        onClick={() => onFold(false)}
        title={t.showPanel}
        className="flex w-full items-center gap-2 text-left"
      >
        {shown ? (
          <>
            <span className="font-medium text-slate-100">
              {t.minutes(mins(shown.arr - shown.dep))}
            </span>
            <span className="flex min-w-0 flex-1 gap-1 overflow-hidden">
              {shown.legs.map(
                (leg, i) =>
                  leg.route !== undefined &&
                  catalog.routes[leg.route] && (
                    <RouteBadge
                      key={i}
                      route={catalog.routes[leg.route]!}
                      className="px-1.5 text-xs"
                    />
                  ),
              )}
            </span>
          </>
        ) : (
          <span className="flex-1 font-medium">{t.plan}</span>
        )}
        <Icon name="up" className="size-4 text-slate-400" />
      </button>
    );

  const order = options ? ranked(options, prefer) : [];
  /** Where the plan's `i`-th option is listed, counting from 1 */
  const place = (i: number) => order.indexOf(options![i]!) + 1;

  const field = (which: End, point: Point | null, on: Aboard | null = null) => (
    <Field
      end={which}
      point={point}
      aboard={on}
      name={point && names.current.get(key(point))}
      catalog={catalog}
      onPick={() => onPick(which)}
      onHere={() => onHere(which)}
      places={places}
      onPlace={(p, name) => {
        if (name) names.current.set(key(p), name);
        onPoint(which, p);
      }}
      onSave={(name, p) => onPlaces(saved(places, name, p.lat, p.lon))}
    />
  );

  return (
    <div className="flex h-full flex-col gap-2 overflow-y-auto">
      <div className="flex items-center">
        <span className="flex-1 font-medium">{t.plan}</span>
        <button
          onClick={() => onFold(true)}
          title={t.hidePanel}
          className="btn-quiet px-2"
        >
          <Icon name="down" className="size-4" />
        </button>
      </div>
      {field("from", start, aboard)}
      {field("to", to)}

      <div className={`flex items-center gap-2 ${aboard ? "hidden" : ""}`}>
        <Label text={t.leaveAt} icon="clock" />
        <input
          type="datetime-local"
          value={at === null ? "" : onClock(at)}
          min={onClock(Date.now() / 1000)}
          max={onClock(Date.now() / 1000 + AHEAD_S)}
          onChange={(e) =>
            setAt(e.target.value === "" ? null : Math.round(new Date(e.target.value).getTime() / 1000))
          }
          className="field min-w-0 flex-1 py-1.5"
        />
        <button
          onClick={() => setAt(null)}
          className={`btn-quiet shrink-0 px-2 text-xs ${at === null ? "text-accent" : ""}`}
        >
          {t.leaveNow}
        </button>
      </div>

      <div className="flex items-center gap-2">
        <Label text={t.walkSpeed} icon="walk" />
        <Speed kmh={speed} onKmh={setSpeed} />
      </div>

      <div className="flex gap-2">
        <button
          onClick={() => void search()}
          disabled={!from || !to || busy}
          className="btn flex-1 disabled:bg-raised/70 disabled:text-slate-500"
        >
          {busy ? t.searching : t.findRoute}
        </button>
        <Order
          prefer={prefer}
          onPrefer={(p) => {
            setPrefer(p);
            holdPrefer(p);
          }}
        />
        <button
          onClick={onSwap}
          disabled={aboard !== null}
          title={t.swap}
          className="btn-quiet px-2 disabled:text-slate-600"
        >
          <Icon name="swap" />
        </button>
      </div>

      {failed !== null && <p className="text-sm text-rose-300">{failed}</p>}
      {options === null && failed === null && (
        <p className="text-sm text-slate-500">{t.planHint}</p>
      )}
      {options !== null && options.length === 0 && (
        <p className="text-sm text-slate-500">{t.noJourney}</p>
      )}

      {options &&
        order.map((j, i) => (
          <Option
            key={i}
            journey={j}
            shown={j === shown}
            onShow={() => show(j)}
            onFollow={() => onFollow(j)}
            onWay={(pick) => takeWay(j, pick)}
            prefer={prefer}
            place={place}
            catalog={catalog}
            onStop={onStop}
            onLine={onLine}
          />
        ))}

      {options !== null && (report || reportSaid) && (
        <p className="flex gap-2 text-xs text-slate-500">
          {reportSaid}
          {report && (
            <button
              onClick={() => void sendReport()}
              className="underline decoration-dotted underline-offset-2 hover:text-slate-300"
            >
              {t.report}
            </button>
          )}
        </p>
      )}
    </div>
  );
}

const END: Record<End, { label: string; icon: IconName }> = {
  from: { label: t.from, icon: "origin" },
  to: { label: t.to, icon: "destination" },
};

function Order({
  prefer,
  onPrefer,
}: {
  prefer: Prefer;
  onPrefer: (p: Prefer) => void;
}) {
  const [open, setOpen] = useState(false);
  return (
    <div className="relative">
      <button
        onClick={() => setOpen(!open)}
        title={`${t.preferBy}: ${t.prefer[prefer]}`}
        className={`btn-quiet h-full px-2 ${open ? "text-accent" : ""}`}
      >
        <Icon name="sort" />
      </button>
      {open && (
        <div className="panel absolute right-0 top-full z-30 mt-1 w-48 p-1 text-sm">
          {PREFERS.map((p) => (
            <button
              key={p}
              onClick={() => {
                onPrefer(p);
                setOpen(false);
              }}
              className={`w-full rounded-md px-2 py-1 text-left hover:bg-raised ${p === prefer ? "text-accent" : ""}`}
            >
              {t.prefer[p]}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

/** An icon standing for a row's name, which it keeps as a tooltip */
function Label({ text, icon }: { text: string; icon: IconName }) {
  return (
    <span title={text} className="flex w-6 shrink-0 justify-center text-slate-500">
      <Icon name={icon} />
    </span>
  );
}

/** One end: a search that, before anything is typed, offers where I am, the
 *  map and the saved places */
function Field({
  end,
  point,
  aboard,
  name,
  catalog,
  onPick,
  onHere,
  places,
  onPlace,
  onSave,
}: {
  end: End;
  point: Point | null;
  /** The vehicle it is on board of, in place of a point */
  aboard: Aboard | null;
  /** What it was called when picked by name */
  name: string | null | undefined;
  catalog: Catalog;
  onPick: () => void;
  onHere: () => void;
  places: Place[];
  onPlace: (at: Point, name?: string) => void;
  onSave: (name: string, at: Point) => void;
}) {
  const [open, setOpen] = useState(false);
  const known = point && places.find((p) => same(point, p));
  const then = (act: () => void) => () => {
    setOpen(false);
    act();
  };
  const row =
    "flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left hover:bg-raised";
  return (
    <div className="flex items-center gap-2">
      <Label text={END[end].label} icon={END[end].icon} />
      <div className="relative min-w-0 flex-1">
        {open ? (
          <StopSearch
            catalog={catalog}
            onGo={(i) => {
              const s = catalog.stops[i]!;
              onPlace({ lat: s.lat, lon: s.lon }, s.name);
            }}
            onPlace={(p) => onPlace({ lat: p.lat, lon: p.lon }, p.name)}
            onSave={(n, lat, lon) => onSave(n, { lat, lon })}
            inline={{
              placeholder: END[end].label,
              onDismiss: () => setOpen(false),
              idle: (
                <>
                  <button onClick={then(onHere)} className={row}>
                    <Icon name="locate" className="size-4" />
                    {t.useHere}
                  </button>
                  <button onClick={then(onPick)} className={row}>
                    <Icon name="map" className="size-4" />
                    {t.chooseOnMap}
                  </button>
                  {point && !known && (
                    <button
                      onClick={then(() => {
                        const n = prompt(t.namePlace)?.trim();
                        if (n) onSave(n, point);
                      })}
                      className={row}
                    >
                      <span className="w-4 text-center">☆</span>
                      {t.savePlace}
                    </button>
                  )}
                  <p className="px-2 pb-0.5 pt-1.5 text-xs uppercase tracking-wide text-slate-500">
                    {t.places}
                  </p>
                  {places.length === 0 && (
                    <p className="px-2 py-1 text-xs text-slate-500">
                      {t.noPlaces}
                    </p>
                  )}
                  {places.map((p) => (
                    <button
                      key={p.name}
                      onClick={then(() => onPlace({ lat: p.lat, lon: p.lon }))}
                      className={row}
                    >
                      <span className="w-4 text-center text-accent">★</span>
                      <span className="truncate">{p.name}</span>
                    </button>
                  ))}
                </>
              ),
            }}
          />
        ) : (
          <button
            onClick={() => setOpen(true)}
            className="flex w-full min-w-0 items-center gap-2 rounded-md bg-raised/70 px-2 py-1.5 text-left text-sm hover:bg-raised"
          >
            <Icon name="search" className="size-4 shrink-0 text-slate-500" />
            {aboard && catalog.routes[aboard.route ?? -1] && (
              <RouteBadge route={catalog.routes[aboard.route!]!} className="shrink-0 px-1.5 text-xs" />
            )}
            <span className="truncate">
              {aboard
                ? t.aboard
                : (known?.name ??
                  name ??
                  (point
                    ? `${point.lat.toFixed(4)}, ${point.lon.toFixed(4)}`
                    : t.findStop))}
            </span>
          </button>
        )}
      </div>
      <button
        onClick={onHere}
        title={t.useHere}
        className="btn-quiet shrink-0 px-2"
      >
        <Icon name="locate" className="size-4" />
      </button>
    </div>
  );
}

function Option({
  journey,
  shown,
  onShow,
  onFollow,
  onWay,
  prefer,
  place,
  catalog,
  onStop,
  onLine,
}: {
  journey: Journey;
  /** Drawn on the map. Until then a click anywhere on the card draws it, and
   *  its stops and lines are not yet links */
  shown: boolean;
  onShow: () => void;
  onFollow: () => void;
  onWay: (pick: WayPick) => Promise<void>;
  prefer: Prefer;
  place: (option: number) => number;
  catalog: Catalog;
  onStop: (i: number) => void;
  onLine: (i: number) => void;
}) {
  const changes = Math.max(0, journey.rides - 1);
  const [backups, setBackups] = useState(false);
  return (
    <div
      onClick={onShow}
      className={`inset-panel cursor-pointer p-2 ${shown ? "ring-2 ring-accent" : ""}`}
    >
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
          {journey.rides > 0 && journey.backup > 0 && (
            <>
              {" · "}
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setBackups(true);
                }}
                title={t.backupHint}
                className="text-emerald-400 underline decoration-dotted underline-offset-2"
              >
                {t.backupCount(journey.backup)}
              </button>
            </>
          )}
        </span>
      </div>
      {backups && (
        <Backups
          journey={journey}
          prefer={prefer}
          place={place}
          catalog={catalog}
          onWay={onWay}
          onClose={() => setBackups(false)}
        />
      )}
      <ol className={`mt-1.5 space-y-1 ${shown ? "" : "pointer-events-none"}`}>
        {journey.legs.map((leg, i) => (
          <li key={i} className="flex items-baseline gap-2 text-sm">
            {leg.kind === "walk" ? (
              <>
                <span title={t.walkLeg(mins(leg.arr - leg.dep))} className="flex w-14 shrink-0 items-center gap-0.5 text-xs text-slate-500">
                  <Icon name="walk" className="size-3.5" />
                  {t.minutes(mins(leg.arr - leg.dep))}
                </span>
                <span className="min-w-0 flex-1 truncate text-slate-400">
                  {leg.b < 0
                    ? t.toDoor
                    : // Consecutive walks are folded before they are sent, so a
                      // walk with a ride either side is the change itself
                      i > 0 && i < journey.legs.length - 1
                      ? t.changeAt(catalog.stops[leg.b]?.name ?? "")
                      : (catalog.stops[leg.b]?.name ?? "")}
                </span>
              </>
            ) : (
              <Ride leg={leg} catalog={catalog} onStop={onStop} onLine={onLine} />
            )}
          </li>
        ))}
      </ol>
      {shown && followable(journey) && (
        <button onClick={onFollow} title={t.followHint} className="btn mt-2 w-full">
          {t.follow}
        </button>
      )}
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
  const [why, setWhy] = useState(false);
  const route = leg.route === undefined ? undefined : catalog.routes[leg.route];
  // An older service says only whether a vehicle was seen
  const confidence = leg.confidence ?? (leg.live ? "live" : "schedule");
  const rests = confidence === "live" ? null : RESTS[confidence];
  return (
    <div className="min-w-0 flex-1">
      <div className="flex items-baseline gap-2">
        <span className="w-14 shrink-0 text-xs tabular-nums text-slate-400">
          {clock(leg.dep)}
        </span>
        {route && (
          <button
            onClick={() => onLine(leg.route!)}
            title={t.showLine}
            className="shrink-0"
          >
            <RouteBadge route={route} className="px-1.5 text-xs" />
          </button>
        )}
        <button
          onClick={() => leg.b >= 0 && onStop(leg.b)}
          className="min-w-0 flex-1 truncate text-left text-slate-200 hover:underline"
        >
          {catalog.stops[leg.b]?.name ?? ""}
        </button>
        {rests && (
          <button
            onClick={() => setWhy(!why)}
            title={rests.why}
            className={`flex shrink-0 items-center gap-0.5 self-center text-xs ${rests.tone}`}
          >
            {rests.word}
            <Icon name="info" className="size-3.5" />
          </button>
        )}
      </div>
      {rests && why && (
        <p className="ml-16 mt-1 text-xs text-slate-400">{rests.why}</p>
      )}
    </div>
  );
}
