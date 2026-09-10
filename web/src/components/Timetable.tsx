import { useEffect, useState } from "react";
import { countdown, nextPerRoute } from "../lib/eta";
import { colour } from "../lib/sprites";
import type { Arrival, Catalog } from "../lib/types";
import { t } from "../lib/i18n";

/** The pinned stops, and the next arrival of each route at each. The clock
 * ticks locally between epochs: the predictions change once a minute, but a
 * countdown that only moves once a minute looks broken. */
export function Timetable({
  catalog,
  stops,
  arrivals,
  onUnpin,
}: {
  catalog: Catalog;
  stops: number[];
  arrivals: Record<string, Arrival[]>;
  onUnpin: (i: number) => void;
}) {
  const [now, setNow] = useState(Date.now() / 1000);
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now() / 1000), 5000);
    return () => clearInterval(id);
  }, []);

  if (!stops.length) {
    return <p className="p-6 text-sm text-slate-500">{t.nothingPinned}</p>;
  }

  return (
    <div className="h-full space-y-4 overflow-y-auto p-4">
      {stops.map((i) => {
        const s = catalog.stops[i];
        if (!s) return null;
        const due = nextPerRoute(arrivals[String(i)] ?? []);
        return (
          <section key={i}>
            <div className="flex items-baseline gap-2">
              <h3 className="truncate font-medium text-slate-100">{s.name}</h3>
              <button
                onClick={() => onUnpin(i)}
                className="text-xs text-slate-600 hover:text-rose-300"
              >
                {t.unpin}
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
                      <span
                        className="w-12 rounded px-1.5 py-0.5 text-center text-sm font-semibold"
                        style={
                          r
                            ? { backgroundColor: colour(r.short, r.type), color: "#0b0f14" }
                            : undefined
                        }
                      >
                        {r?.short ?? "?"}
                      </span>
                      <span className="flex-1 truncate text-sm text-slate-400">{r?.long}</span>
                      <span className="tabular-nums text-sm text-slate-100">
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
