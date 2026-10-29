import { stopTitle } from "../lib/catalog";
import { countdown, nextPerRoute } from "../lib/eta";
import { RouteChip } from "./RouteChip";
import type { Arrival, Catalog } from "../lib/types";
import { t } from "../lib/i18n";
import { Icon } from "./Icon";
import { Close } from "./Cross";

/** What is due here, then every route that calls here. Every route chip on it,
 * due or not, watches its route or stops watching it, and opens its line from
 * its `›`. What is due covers every route through the stop, watched or not. */
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
  lowFloor = false,
}: {
  catalog: Catalog;
  stop: number;
  arrivals: Arrival[] | undefined;
  pinned: boolean;
  onPin: () => void;
  /** The routes picked, by id */
  watching: Set<string>;
  onToggle: (id: string) => void;
  /** The line, from a chip's `›` */
  onRoute: (i: number) => void;
  onClose: () => void;
  /** Mark the vehicles the feed calls low floor */
  lowFloor?: boolean;
}) {
  const s = catalog.stops[stop];
  if (!s) return null;
  const { name, code } = stopTitle(s);
  const due = nextPerRoute(arrivals ?? []).filter((a) => catalog.routes[a.route]);

  return (
    <div className="panel pointer-events-auto p-3">
      <div className="flex items-start gap-2">
        <div className="min-w-0 flex-1">
          {/* The code in brackets, as every other place names the stop */}
          <div className="flex items-baseline gap-1.5">
            <h3 className="truncate font-medium text-slate-100">{name}</h3>
            {code && <span className="shrink-0 text-sm text-slate-500">({code})</span>}
          </div>
          <p className="text-xs text-slate-500">{t.routeCount(s.routes.length)}</p>
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
          {due.map((a) => {
            const r = catalog.routes[a.route]!;
            return (
              <li key={a.route}>
                <RouteChip
                  route={r}
                  watched={watching.has(r.id)}
                  onWatch={() => onToggle(r.id)}
                  onLine={() => onRoute(a.route)}
                >
                  <Due arrival={a} lowFloor={lowFloor} />
                </RouteChip>
              </li>
            );
          })}
        </ul>
      )}
      <Doubts catalog={catalog} due={due} />

      <h4 className="mt-3 text-xs uppercase tracking-wide text-slate-500">{t.callsHere}</h4>
      <div className="mt-1 flex flex-wrap gap-1">
        {s.routes.map((i) => {
          const r = catalog.routes[i];
          if (!r) return null;
          return (
            <RouteChip
              key={r.id}
              route={r}
              watched={watching.has(r.id)}
              onWatch={() => onToggle(r.id)}
              onLine={() => onRoute(i)}
            />
          );
        })}
      </div>
    </div>
  );
}

/** The countdown on a route's chip: amber when its vehicle is doubted, italic
 *  on a trip yet to start, and marked when low floor and asked to */
function Due({ arrival: a, lowFloor }: { arrival: Arrival; lowFloor: boolean }) {
  const tone = a.doubt ? "text-amber-300" : "text-slate-400";
  return (
    <span className={`flex items-center gap-1 text-xs ${tone} ${a.planned ? "italic" : ""}`}>
      {countdown(a.t)}
      {lowFloor && a.low_floor && (
        <span title={t.lowFloor} aria-label={t.lowFloor} className="text-accent">
          <Icon name="wheelchair" className="size-3.5" />
        </span>
      )}
    </span>
  );
}

/** Why an amber time is amber, one line a route, only while one is */
function Doubts({ catalog, due }: { catalog: Catalog; due: Arrival[] }) {
  const doubted = due.filter((a) => a.doubt);
  if (doubted.length === 0) return null;
  return (
    <div className="mt-1.5 space-y-0.5 text-xs text-amber-300">
      {doubted.map((a) => (
        <p key={a.route}>{t.doubt[a.doubt!](catalog.routes[a.route]!.short)}</p>
      ))}
    </div>
  );
}

