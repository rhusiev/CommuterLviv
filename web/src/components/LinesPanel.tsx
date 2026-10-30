import { useEffect, useMemo, useState } from "react";
import { api } from "../lib/api";
import { clock, countdown, mins } from "../lib/eta";
import { lineHours, lineRows, routesNear, type Direction } from "../lib/lines";
import { hereOnce, ONE_FIX, type NoFix } from "../lib/position";
import type { Arrival, Catalog, Route, RouteSet } from "../lib/types";
import { t } from "../lib/i18n";
import { RouteBadge } from "./RouteBadge";
import { RouteChip } from "./RouteChip";
import { Icon, type IconName } from "./Icon";
import { Menu } from "./Menu";

/** The routes, to watch or to open one line of; and the one line open.
 *
 * A set is the selection at the moment it was saved: editing the selection
 * does not touch it until it is saved again. Renaming and deleting sets is in
 * the Mine tab. */

/** Around a five-minute walk. Chosen, not derived */
export const NEAR_LINES_M = 500;
/** A fix this old still says where you are for picking nearby routes */
const NEAR_FIX_AGE_MS = 60_000;
const TICK_MS = 15_000;

type BrowseProps = {
  catalog: Catalog;
  picked: Set<string>;
  onToggle: (id: string) => void;
  /** Watches every route in the catalog, or none, as no saved set */
  onPick: (all: boolean) => void;
  /** The line, from a chip's `›` or a recently opened row */
  onOpen: (i: number) => void;
  /** Route ids, latest first */
  recent: string[];
  sets: RouteSet[];
  active: string | null;
  onActivate: (set: RouteSet) => void;
  onCreate: (name: string) => Promise<void>;
  onUpdate: (set: RouteSet) => Promise<void>;
};

/** Two things, kept apart: what the map watches, in one toolbar - a box that
 *  watches every route or none, the saved sets, and saving the ticks as one -
 *  and, below, the list of routes, which its own filters only narrow */
export function LinesBrowse(p: BrowseProps) {
  const [onlyWatched, setOnlyWatched] = useState(false);
  const [near, setNear] = useState<Set<number> | null>(null);
  const [why, setWhy] = useState("");
  const [query, setQuery] = useState("");

  const toggleNear = () => {
    setWhy("");
    if (near) return setNear(null);
    hereOnce({ ...ONE_FIX, maximumAge: NEAR_FIX_AGE_MS }).then(
      (pos) => {
        const at = { lat: pos.coords.latitude, lon: pos.coords.longitude };
        const found = routesNear(p.catalog, at, NEAR_LINES_M);
        setNear(found);
        if (found.size === 0) setWhy(t.nothingNearLines(NEAR_LINES_M));
      },
      (no: NoFix) => setWhy(t.noFix[no]),
    );
  };

  const groups = useMemo(() => {
    const q = query.trim().toLowerCase();
    const keep = (r: Route, i: number) =>
      (!onlyWatched || p.picked.has(r.id)) &&
      (!near || near.has(i)) &&
      (!q || r.short.toLowerCase().includes(q) || r.long.toLowerCase().includes(q));
    return byKind(p.catalog, keep);
  }, [p.catalog, p.picked, onlyWatched, near, query]);

  const recent = p.recent
    .map((id) => p.catalog.routes.findIndex((r) => r.id === id))
    .filter((i) => i >= 0);

  return (
    <div className="flex h-full flex-col gap-2 overflow-hidden">
      <Toolbar {...p} />
      <input
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        placeholder={t.filter}
        className="field py-1.5"
      />
      <div className="flex flex-wrap gap-1">
        <Narrow on={near !== null} onClick={toggleNear} icon="locate">
          {t.nearLines}
        </Narrow>
        <Narrow on={onlyWatched} onClick={() => setOnlyWatched((on) => !on)} icon="check">
          {t.onlyWatched}
        </Narrow>
      </div>
      {why && <p className="text-xs text-slate-500">{why}</p>}
      {onlyWatched && p.picked.size === 0 && <p className="text-xs text-slate-500">{t.noneWatched}</p>}
      {recent.length > 0 && (
        <section>
          <h2 className="text-xs text-slate-500">{t.recentLines}</h2>
          <div className="mt-1 flex flex-wrap gap-1">
            {recent.map((i) => {
              const r = p.catalog.routes[i]!;
              return (
                <RouteChip
                  key={r.id}
                  route={r}
                  watched={p.picked.has(r.id)}
                  onWatch={() => p.onToggle(r.id)}
                  onLine={() => p.onOpen(i)}
                />
              );
            })}
          </div>
        </section>
      )}
      <section className="flex min-h-0 flex-1 flex-col">
        <RouteGrid groups={groups} picked={p.picked} onToggle={p.onToggle} onOpen={p.onOpen} />
      </section>
    </div>
  );
}

/** Grouped by vehicle type, in catalog order: tram 1 and bus 1 are different
 * lines that would otherwise sit in one undivided grid */
function byKind(cat: Catalog, keep: (r: Route, i: number) => boolean) {
  const out = new Map<string, (readonly [Route, number])[]>();
  cat.routes.forEach((r, i) => {
    if (keep(r, i)) out.set(r.type, [...(out.get(r.type) ?? []), [r, i] as const]);
  });
  return [...out];
}

/** A filter on the list alone, on or off: outlined, with its icon, so it does
 *  not read as one of the choices of what the map watches above */
function Narrow({
  on,
  onClick,
  icon,
  children,
}: {
  on: boolean;
  onClick: () => void;
  icon: IconName;
  children: React.ReactNode;
}) {
  return (
    <button
      aria-pressed={on}
      onClick={onClick}
      className={`flex items-center gap-1 rounded-full px-3 py-1 text-sm ring-1 transition-colors ${
        on ? "text-accent ring-accent/60" : "text-slate-400 ring-hair hover:text-slate-200"
      }`}
    >
      <Icon name={icon} className="size-4" />
      {children}
    </button>
  );
}

/** What the map watches, in one row: a box that, as a mail client's select-all,
 *  watches every route when none is and none otherwise, how many are watched,
 *  the saved sets, and saving these as one */
function Toolbar(p: BrowseProps) {
  const [naming, setNaming] = useState(false);
  const [menu, setMenu] = useState(false);
  const [name, setName] = useState("");
  const [error, setError] = useState("");
  const total = p.catalog.routes.length;
  const n = p.picked.size;
  const current = p.sets.find((s) => s.id === p.active);
  const changed =
    current !== undefined && (current.routes.length !== n || current.routes.some((id) => !p.picked.has(id)));

  const guard = (fn: () => Promise<void>) => async () => {
    setError("");
    try {
      await fn();
    } catch (err) {
      setError(err instanceof Error ? err.message : t.failed);
    }
  };

  return (
    <section>
      <div className="flex items-center gap-2">
        <button
          role="checkbox"
          aria-checked={n === 0 ? false : n === total ? true : "mixed"}
          title={n === 0 ? t.watchAll : t.watchNone}
          onClick={() => p.onPick(n === 0)}
          className={`flex size-5 shrink-0 items-center justify-center rounded border-2 ${
            n === 0 ? "border-slate-500 hover:border-slate-300" : "border-accent bg-accent text-plate"
          }`}
        >
          {n > 0 && <Icon name={n === total ? "check" : "minus"} className="size-3.5" />}
        </button>
        <span className="min-w-0 flex-1 truncate text-sm text-slate-200">{t.onMapOf(n, total)}</span>
        {p.sets.length > 0 && (
          <select
            value={current?.id ?? ""}
            onChange={(e) => {
              const s = p.sets.find((x) => x.id === e.target.value);
              if (s) p.onActivate(s);
            }}
            aria-label={t.setsMenu}
            className="field max-w-32 py-1 text-sm"
          >
            {current === undefined && (
              <option value="" disabled>
                {t.setsMenu}
              </option>
            )}
            {p.sets.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </select>
        )}
        <span className="relative">
          <Menu icon="more" label={t.setActions} open={menu} quiet onToggle={setMenu}>
            <button
              disabled={n === 0}
              onClick={() => {
                setMenu(false);
                setNaming(true);
              }}
              className="w-full rounded-md px-2 py-1.5 text-left text-sm enabled:hover:bg-raised disabled:text-slate-600"
            >
              {t.saveAsSet}
            </button>
            {changed && (
              <button
                onClick={() => {
                  setMenu(false);
                  void guard(() => p.onUpdate(current))();
                }}
                className="w-full rounded-md px-2 py-1.5 text-left text-sm hover:bg-raised"
              >
                {t.updateSet(current.name)}
              </button>
            )}
          </Menu>
        </span>
      </div>
      {naming && (
        <form
          className="mt-2 flex gap-1"
          onSubmit={(e) => {
            e.preventDefault();
            if (!name.trim()) return;
            void guard(async () => {
              await p.onCreate(name.trim());
              setName("");
              setNaming(false);
            })();
          }}
        >
          <input
            autoFocus
            value={name}
            onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => e.key === "Escape" && setNaming(false)}
            placeholder={t.nameSet}
            className="field min-w-0 flex-1 py-1.5"
          />
          <button className="btn-quiet px-2 py-0" title={t.add}>
            <Icon name="plus" className="size-4" />
          </button>
        </form>
      )}
      {error && <p className="mt-1 text-xs text-rose-400">{error}</p>}
    </section>
  );
}

function RouteGrid({
  groups,
  picked,
  onToggle,
  onOpen,
}: {
  groups: [string, (readonly [Route, number])[]][];
  picked: Set<string>;
  onToggle: (id: string) => void;
  onOpen: (i: number) => void;
}) {
  return (
    <div data-chips className="mt-2 min-h-0 space-y-2 overflow-y-auto">
      {groups.map(([type, routes]) => (
        <div key={type}>
          <h3 className="mb-1 text-xs text-slate-500">{t.kinds[type] ?? type}</h3>
          {/* Columns, so a chip wider than the rest does not shift the ones after it */}
          <div className="grid grid-cols-[repeat(auto-fill,minmax(5.5rem,1fr))] gap-1">
            {routes.map(([r, i]) => (
              <RouteChip
                key={r.id}
                route={r}
                watched={picked.has(r.id)}
                onWatch={() => onToggle(r.id)}
                onLine={() => onOpen(i)}
              />
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

type LineProps = {
  catalog: Catalog;
  route: number;
  /** Each way the line runs; empty until the shapes are in */
  ways: Direction[];
  way: number;
  onWay: (way: number) => void;
  arrivals: Record<string, Arrival[]>;
  onStop: (i: number) => void;
  onBack: () => void;
  /** Down to its title alone, so the map shows the line */
  folded: boolean;
  onFold: (folded: boolean) => void;
};

/** One line: its stops one way, with what this route has due at each and
 * where its vehicles are */
export function LineView(p: LineProps) {
  const [now, setNow] = useState(() => Date.now() / 1000);
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now() / 1000), TICK_MS);
    return () => clearInterval(id);
  }, []);
  const r = p.catalog.routes[p.route]!;
  const shown = p.ways[p.way];
  const rows = shown ? lineRows(shown.stops, p.arrivals, p.route) : [];
  const last = shown?.stops.at(-1);
  const dep = useDepartures(p.route, shown?.stops[0]);

  return (
    <div className="flex h-full flex-col gap-2 overflow-hidden">
      <div className="flex items-center gap-2">
        <button onClick={p.onBack} title={t.back} aria-label={t.back} className="-m-2 p-2 text-slate-400 hover:text-slate-200">
          <Icon name="left" />
        </button>
        {/* Folded, the title opens it again, as a folded journey's strip does */}
        <button
          onClick={() => p.folded && p.onFold(false)}
          disabled={!p.folded}
          title={p.folded ? t.showStops : undefined}
          className="flex min-w-0 flex-1 items-center gap-2 text-left"
        >
          <RouteBadge route={r} className="px-1.5 py-0.5 text-xs" />
          <span className="min-w-0 flex-1 truncate text-sm text-slate-300">{r.long}</span>
        </button>
        {/* Folded up under the search bar, like the journey: up folds, down opens */}
        <button
          onClick={() => p.onFold(!p.folded)}
          title={p.folded ? t.showStops : t.hideStops}
          aria-expanded={!p.folded}
          className="btn-quiet px-2"
        >
          <Icon name={p.folded ? "down" : "up"} className="size-4" />
        </button>
      </div>
      {!p.folded && <LineBody {...p} rows={rows} last={last} now={now} dep={dep} />}
    </div>
  );
}

/** The route's departures today from the stop a way starts at; empty until
 * known, and when the timetable cannot say */
function useDepartures(route: number, stop: number | undefined) {
  const key = `${route}:${stop}`;
  const [held, setHeld] = useState<{ key: string; dep: number[] } | null>(null);
  useEffect(() => {
    if (stop === undefined) return;
    let dropped = false;
    const load = async () => {
      try {
        const answer = await api.departures(route, stop);
        if (!dropped) setHeld({ key, dep: answer.dep });
      } catch {
        // without them the line is shown as before, its hours left out
      }
    };
    void load();
    return () => {
      dropped = true;
    };
  }, [key, route, stop]);
  return held?.key === key ? held.dep : [];
}

/** When the line runs and how often, as plain chips: nothing to tap */
export function LineHours({ dep, now }: { dep: number[]; now: number }) {
  const h = lineHours(dep, now);
  if (!h) return null;
  const chips = [t.firstDeparture(clock(h.first)), t.lastDeparture(clock(h.last))];
  if (h.every !== null) chips.push(t.everyMinutes(mins(h.every)));
  return (
    <div title={t.lineHoursHint} className="flex flex-wrap gap-1 text-xs tabular-nums text-slate-400">
      {chips.map((c) => (
        <span key={c} className="rounded-full border border-slate-700 px-2 py-0.5">
          {c}
        </span>
      ))}
    </div>
  );
}

/** Below the line's title: when it runs, its way, and its stops in order */
function LineBody(
  p: LineProps & { rows: ReturnType<typeof lineRows>; last: number | undefined; now: number; dep: number[] },
) {
  const { rows, last, now } = p;
  return (
    <>
      <LineHours dep={p.dep} now={now} />
      <div className="flex items-center gap-1">
        {last !== undefined && (
          <button
            onClick={() => p.onWay((p.way + 1) % p.ways.length)}
            disabled={p.ways.length < 2}
            title={t.otherWay}
            className="min-w-0 flex-1 truncate rounded-full bg-raised/70 px-3 py-1 text-left text-sm text-slate-200 enabled:hover:bg-raised"
          >
            → {p.catalog.stops[last]!.name}
          </button>
        )}
      </div>
      {p.ways.length > 0 && rows.length === 0 && <p className="text-xs text-slate-500">{t.noLineStops}</p>}
      <ol className="min-h-0 flex-1 overflow-y-auto">
        {rows.map(({ stop, next, vehs }) => (
          <li key={stop}>
            <button
              onClick={() => p.onStop(stop)}
              className="flex w-full items-center gap-2 rounded-md px-1 py-1.5 text-left hover:bg-raised/70"
            >
              <span className="flex w-4 shrink-0 justify-center">
                {vehs.length > 0 ? (
                  <span title={t.vehicleHere} aria-label={t.vehicleHere} className="size-2.5 rounded-full bg-accent" />
                ) : (
                  <span className="size-1.5 rounded-full bg-slate-600" />
                )}
              </span>
              <span className="min-w-0 flex-1 truncate text-sm text-slate-300">{p.catalog.stops[stop]!.name}</span>
              {next && (
                <span
                  title={next.planned ? t.planned : undefined}
                  className={`text-xs tabular-nums ${next.planned ? "text-slate-500" : "text-slate-300"}`}
                >
                  {countdown(next.t, now)}
                </span>
              )}
            </button>
          </li>
        ))}
      </ol>
    </>
  );
}
