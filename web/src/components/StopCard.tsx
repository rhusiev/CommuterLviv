import { countdown, nextPerRoute } from "../lib/eta";
import { RouteBadge } from "./RouteBadge";
import type { Arrival, Catalog } from "../lib/types";
import { t } from "../lib/i18n";

/** The route list is complete; the times only cover the routes on the map,
 * because only those are being predicted for. */
export function StopCard({
  catalog,
  stop,
  arrivals,
  pinned,
  onPin,
  onRoute,
  onClose,
}: {
  catalog: Catalog;
  stop: number;
  arrivals: Arrival[] | undefined;
  pinned: boolean;
  onPin: () => void;
  onRoute: (i: number) => void;
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
        {/* An icon rather than a word, whose length would change on tap and
            shift the ✕ beside it */}
        <button
          onClick={onPin}
          title={pinned ? t.unpin : t.pin}
          className={`rounded-control p-1.5 transition-colors ${
            pinned
              ? "bg-accent/15 text-accent"
              : "bg-raised/70 text-slate-400 hover:text-slate-200"
          }`}
        >
          <svg
            viewBox="0 0 24 24"
            className="size-5"
            fill={pinned ? "currentColor" : "none"}
            stroke="currentColor"
            strokeWidth="2"
            strokeLinejoin="round"
            strokeLinecap="round"
            aria-hidden
          >
            <path d="M9.5 3h5l-.5 6.5 3 2.5v1.5H7V12l3-2.5z" />
            <path d="M12 13.5V21" />
          </svg>
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
            <li key={i}>
              <button
                onClick={() => onRoute(i)}
                title={t.showLine}
                className="flex items-center gap-1 rounded-control bg-raised/70 py-0.5 pl-0.5 pr-1.5 hover:bg-raised"
              >
                <RouteBadge route={r} className="px-1.5 py-0.5 text-xs" />
                <span className="text-xs text-slate-400">{a ? countdown(a.t) : "-"}</span>
              </button>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
