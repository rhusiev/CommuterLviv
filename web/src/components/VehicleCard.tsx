import { useEffect, useState } from "react";
import { api, EPOCH_MS } from "../lib/api";
import { Close } from "./Cross";
import { countdown } from "../lib/eta";
import { t } from "../lib/i18n";
import { RouteChip } from "./RouteChip";
import type { Aboard, Catalog, VehicleStops } from "../lib/types";
import { Icon } from "./Icon";

export function VehicleCard({
  catalog,
  veh,
  onStop,
  watching,
  onToggle,
  onRoute,
  onAboard,
  onClose,
  following = false,
  onFollow = () => {},
  lowFloor = false,
}: {
  catalog: Catalog;
  veh: number;
  onStop: (i: number) => void;
  /** The routes picked, by id */
  watching: Set<string>;
  onToggle: (id: string) => void;
  /** The line, from the route chip's `›` */
  onRoute: (i: number) => void;
  /** Plans a journey from on board it */
  onAboard: (from: Aboard) => void;
  onClose: () => void;
  /** The map keeps it in the middle */
  following?: boolean;
  onFollow?: (on: boolean) => void;
  /** Mark it if the feed calls it low floor */
  lowFloor?: boolean;
}) {
  // Keyed by `veh` where it is used, so these start afresh for each vehicle
  const [said, setSaid] = useState<VehicleStops | null>(null);
  /** Seconds since its last report, as of the answer */
  const [ago, setAgo] = useState<number | null>(null);
  const calls = said?.stops ?? null;
  const [gone, setGone] = useState(false);

  useEffect(() => {
    let dropped = false;
    const load = async () => {
      try {
        const answer = await api.vehicle(veh);
        if (dropped) return;
        setSaid(answer);
        setAgo(answer.seen === undefined ? null : Date.now() / 1000 - answer.seen);
        setGone(answer.stops.length === 0);
      } catch {
        if (!dropped) setGone(true);
      }
    };
    void load();
    const again = window.setInterval(load, EPOCH_MS);
    return () => {
      dropped = true;
      clearInterval(again);
    };
  }, [veh]);

  const at = calls?.[0]?.route;
  const route = at === undefined ? null : catalog.routes[at];

  return (
    <div className="panel pointer-events-auto p-3">
      <div className="flex items-start gap-2">
        {route && at !== undefined && (
          <RouteChip
            route={route}
            watched={watching.has(route.id)}
            onWatch={() => onToggle(route.id)}
            onLine={() => onRoute(at)}
            className="shrink-0"
          />
        )}
        <div className="min-w-0 flex-1">
          <h3 className="truncate font-medium text-slate-100">
            {t.stopsAhead}
          </h3>
          {route && (
            <p className="flex items-center gap-1 text-xs text-slate-500">
              <span className="truncate">{route.long}</span>
              {said?.fleet && <span className="shrink-0">· {t.fleet(said.fleet)}</span>}
              {lowFloor && said?.low_floor && (
                <span title={t.lowFloor} aria-label={t.lowFloor} className="shrink-0 text-accent">
                  <Icon name="wheelchair" className="size-3.5" />
                </span>
              )}
            </p>
          )}
          <LastSeen ago={ago} />
        </div>
        <button
          onClick={() => onFollow(!following)}
          title={t.followVehicle}
          aria-pressed={following}
          className={`rounded-control p-1.5 transition-colors ${
            following ? "bg-accent/15 text-accent" : "bg-raised/70 text-slate-400 hover:text-slate-200"
          }`}
        >
          <Icon name="follow" />
        </button>
        <Close onClick={onClose} />
      </div>

      {calls === null && !gone && (
        <p className="mt-2 text-sm text-slate-500">…</p>
      )}
      {gone && <p className="mt-2 text-sm text-slate-500">{t.vehicleGone}</p>}

      <ul className="mt-2 max-h-64 overflow-y-auto">
        {(calls ?? []).map((c) => {
          const s = catalog.stops[c.stop];
          if (!s) return null;
          return (
            <li key={c.stop}>
              <button
                onClick={() => onStop(c.stop)}
                className="flex w-full items-baseline gap-2 rounded-md px-1 py-1 text-left transition-colors hover:bg-raised/70"
              >
                <span className="min-w-0 flex-1 truncate text-sm text-slate-200">
                  {s.name}
                </span>
                <span className="text-xs tabular-nums text-slate-400">
                  {countdown(c.t)}
                </span>
              </button>
            </li>
          );
        })}
      </ul>
      {calls !== null && calls.length > 0 && (
        <button
          onClick={() => onAboard({ veh, route: at ?? null })}
          title={t.onItHint}
          className="btn mt-2 w-full"
        >
          {t.onIt}
        </button>
      )}
    </div>
  );
}

/** A report older than this and the card says when it was: the map fades the
 *  vehicle from the same age (`FRESH` in `live/state.py`) */
const STALE_S = 30;
const MINUTE_S = 60;

/** When the vehicle last reported, said only once that is worth knowing */
function LastSeen({ ago }: { ago: number | null }) {
  if (ago === null || ago < STALE_S) return null;
  const said = ago < MINUTE_S ? t.seconds(Math.round(ago)) : t.minutes(Math.round(ago / MINUTE_S));
  return <p className="text-xs text-amber-300">{t.lastSeen(said)}</p>;
}

