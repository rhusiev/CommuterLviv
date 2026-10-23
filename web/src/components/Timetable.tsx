import { useEffect, useState } from "react";
import { countdown, nextPerRoute } from "../lib/eta";
import { useReorder } from "../lib/reorder";
import type { Arrival, Catalog } from "../lib/types";
import { t } from "../lib/i18n";
import { RouteChip } from "./RouteChip";
import { Icon } from "./Icon";
import { Grip } from "./Grip";

/** How often the countdowns move on */
const TICK_MS = 5000;

/** The pinned stops, each with what is due there, in the order the account
 * chose; a stop is dragged by its grip to change it.
 *
 * The clock ticks locally between epochs: the predictions change once a
 * minute, but a countdown that only moves once a minute looks broken. */
export function Timetable({
  catalog,
  stops,
  arrivals,
  onPins,
  onStop,
  watching,
  onToggle,
  onRoute,
}: {
  catalog: Catalog;
  stops: number[];
  arrivals: Record<string, Arrival[]>;
  onPins: (next: number[]) => void;
  onStop: (i: number) => void;
  /** The routes picked, by id */
  watching: Set<string>;
  onToggle: (id: string) => void;
  /** The line, from a chip's `›` */
  onRoute: (i: number) => void;
}) {
  const [now, setNow] = useState(() => Date.now() / 1000);
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now() / 1000), TICK_MS);
    return () => clearInterval(id);
  }, []);
  const pinned = useReorder(stops, onPins);

  if (!stops.length) {
    return <p className="text-sm text-slate-500">{t.nothingPinned}</p>;
  }

  return (
    <div className="space-y-4">
      {pinned.shown.map((i, at) => {
        const s = catalog.stops[i];
        if (!s) return null;
        const due = nextPerRoute(arrivals[String(i)] ?? []);
        return (
          <section key={s.id} {...pinned.row(at)}>
            <div className="flex items-center gap-1">
              <Grip />
              <button
                onClick={() => onStop(i)}
                title={t.showOnMap}
                className="min-w-0 truncate rounded-md px-1 py-1 text-left font-medium text-slate-100 hover:bg-raised/70"
              >
                {s.name}
              </button>
              <button
                onClick={() => onPins(stops.filter((p) => p !== i))}
                title={t.unpin}
                className="text-accent hover:text-rose-300"
              >
                <Icon name="pin" filled className="size-4" />
              </button>
            </div>
            {due.length === 0 ? (
              <p className="mt-1 text-sm text-slate-600">{t.nothingDue}</p>
            ) : (
              <ul className="mt-1 divide-y divide-hair">
                {due.map((a) => {
                  const r = catalog.routes[a.route];
                  return (
                    <li key={a.route} className="flex items-center gap-2 py-1.5">
                      {r ? (
                        <RouteChip
                          route={r}
                          watched={watching.has(r.id)}
                          onWatch={() => onToggle(r.id)}
                          onLine={() => onRoute(a.route)}
                          className="w-24 shrink-0"
                        />
                      ) : (
                        <span className="w-24 text-center text-sm text-slate-500">?</span>
                      )}
                      <span className="flex-1 truncate text-sm text-slate-400">{r?.long}</span>
                      <span
                        className={`tabular-nums text-sm text-slate-100 ${a.planned ? "italic" : ""}`}
                        title={a.planned ? t.planned : undefined}
                      >
                        {countdown(a.t, now)}
                      </span>
                    </li>
                  );
                })}
              </ul>
            )}
          </section>
        );
      })}
    </div>
  );
}
