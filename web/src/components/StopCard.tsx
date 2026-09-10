import { countdown, nextPerRoute } from "../lib/eta";
import { colour } from "../lib/sprites";
import type { Arrival, Catalog } from "../lib/types";
import { t } from "../lib/i18n";

/** What is at this stop: every route that passes through it, and when the next
 * one of each is due. The route list comes from the catalog and is complete;
 * the times only cover the routes currently on the map, because only those are
 * being predicted for. */
export function StopCard({
  catalog,
  stop,
  arrivals,
  pinned,
  onPin,
  onClose,
}: {
  catalog: Catalog;
  stop: number;
  arrivals: Arrival[] | undefined;
  pinned: boolean;
  onPin: () => void;
  onClose: () => void;
}) {
  const s = catalog.stops[stop];
  if (!s) return null;
  const due = new Map(nextPerRoute(arrivals ?? []).map((a) => [a.route, a]));

  return (
    <div className="panel pointer-events-auto p-3">
      <div className="flex items-start gap-2">
        <div className="min-w-0 flex-1">
          <h3 className="truncate font-medium text-slate-100">{s.name}</h3>
          <p className="text-xs text-slate-500">
            {s.code} · {t.routeCount(s.routes.length)}
          </p>
        </div>
        <button
          onClick={onPin}
          className={`rounded-control px-2 py-1 text-xs transition-colors ${
            pinned
              ? "bg-accent/15 text-accent"
              : "bg-raised/70 text-slate-400 hover:text-slate-200"
          }`}
        >
          {pinned ? t.pinned : t.pin}
        </button>
        <button onClick={onClose} className="px-1 text-slate-500 hover:text-slate-200">
          ✕
        </button>
      </div>

      <ul className="mt-2 flex flex-wrap gap-1">
        {s.routes.map((i) => {
          const r = catalog.routes[i];
          if (!r) return null;
          const a = due.get(i);
          return (
            <li
              key={i}
              className="flex items-center gap-1 rounded-control bg-raised/70 py-0.5 pl-0.5 pr-1.5"
            >
              <span
                className="rounded px-1.5 py-0.5 text-xs font-semibold"
                style={{ backgroundColor: colour(r.short, r.type), color: "#0b0f14" }}
              >
                {r.short}
              </span>
              <span className="text-xs text-slate-400">{a ? countdown(a.t) : "-"}</span>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
