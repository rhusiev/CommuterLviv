import { stopTitle } from "../lib/catalog";
import { countdown, nextPerRoute } from "../lib/eta";
import { RouteBadge } from "./RouteBadge";
import type { Arrival, Catalog } from "../lib/types";
import { t } from "../lib/i18n";
import { Icon } from "./Icon";
import { Close } from "./Cross";

/** What is due here, then every route that calls here, which a click watches
 * or stops watching. The times only cover the routes on the map, because only
 * those are being predicted for. */
export function StopCard({
  catalog,
  stop,
  arrivals,
  pinned,
  onPin,
  watching,
  onToggle,
  onRoute,
  onClose,
}: {
  catalog: Catalog;
  stop: number;
  arrivals: Arrival[] | undefined;
  pinned: boolean;
  onPin: () => void;
  /** The routes picked, by id */
  watching: Set<string>;
  onToggle: (id: string) => void;
  /** The line, from a click on what is due; a click on a route that calls
   *  here already toggles it, so there this is on `onContextMenu` */
  onRoute: (i: number) => void;
  onClose: () => void;
}) {
  const s = catalog.stops[stop];
  if (!s) return null;
  const { name, code } = stopTitle(s);
  const due = nextPerRoute(arrivals ?? []).filter((a) => catalog.routes[a.route]);

  return (
    <div className="panel pointer-events-auto p-3">
      <div className="flex items-start gap-2">
        <div className="min-w-0 flex-1">
          <h3 className="truncate font-medium text-slate-100">{name}</h3>
          <p className="text-xs text-slate-500">
            {[code, t.routeCount(s.routes.length)].filter(Boolean).join(" · ")}
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
          <Icon name="pin" filled={pinned} />
        </button>
        <Close onClick={onClose} />
      </div>

      {due.length === 0 ? (
        <p className="mt-2 text-xs text-slate-500">{t.nothingDue}</p>
      ) : (
        <ul className="mt-2 flex flex-wrap gap-1">
          {due.map((a) => (
            <li key={a.route}>
              <button
                onClick={() => onRoute(a.route)}
                title={t.showLine}
                className="flex items-center gap-1 rounded-control bg-raised/70 py-0.5 pl-0.5 pr-1.5 hover:bg-raised"
              >
                <RouteBadge route={catalog.routes[a.route]!} className="px-1.5 py-0.5 text-xs" />
                <span className={`text-xs text-slate-400 ${a.planned ? "italic" : ""}`}>
                  {countdown(a.t)}
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}

      <h4 className="mt-3 text-xs uppercase tracking-wide text-slate-500">{t.callsHere}</h4>
      <div className="mt-1 flex flex-wrap gap-1">
        {s.routes.map((i) => {
          const r = catalog.routes[i];
          if (!r) return null;
          const on = watching.has(r.id);
          return (
            <button
              key={r.id}
              onClick={() => onToggle(r.id)}
              // `onContextMenu` covers both right-click and touch long-press
              onContextMenu={(e) => {
                e.preventDefault();
                onRoute(i);
              }}
            >
              <RouteBadge
                route={r}
                muted={!on}
                className={`px-2 py-1 text-sm ${
                  on ? "" : "bg-raised/70 text-slate-400 hover:bg-raised"
                }`}
              />
            </button>
          );
        })}
      </div>
      <p className="mt-1.5 text-xs text-slate-500">{t.holdForLine}</p>
    </div>
  );
}
