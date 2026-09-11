import { useEffect, useState } from "react";
import { api } from "../lib/api";
import { countdown } from "../lib/eta";
import { t } from "../lib/i18n";
import { RouteBadge } from "./RouteBadge";
import type { Call, Catalog } from "../lib/types";

export function VehicleCard({
  catalog,
  veh,
  onStop,
  onRoute,
  onClose,
}: {
  catalog: Catalog;
  veh: number;
  onStop: (i: number) => void;
  onRoute: (i: number) => void;
  onClose: () => void;
}) {
  const [calls, setCalls] = useState<Call[] | null>(null);
  const [gone, setGone] = useState(false);

  useEffect(() => {
    let dropped = false;
    setCalls(null);
    setGone(false);
    const load = async () => {
      try {
        const answer = await api.vehicle(veh);
        if (dropped) return;
        setCalls(answer.stops);
        setGone(answer.stops.length === 0);
      } catch {
        if (!dropped) setGone(true);
      }
    };
    void load();
    // The model's epoch is 60 s, so refetch on the same period
    const again = window.setInterval(load, 60_000);
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
          <button onClick={() => onRoute(at)} title={t.routeLine} className="shrink-0">
            <RouteBadge route={route} className="px-1.5 py-0.5 text-xs" />
          </button>
        )}
        <div className="min-w-0 flex-1">
          <h3 className="truncate font-medium text-slate-100">
            {t.stopsAhead}
          </h3>
          {route && (
            <p className="truncate text-xs text-slate-500">{route.long}</p>
          )}
        </div>
        <button
          onClick={onClose}
          className="px-1 text-slate-500 hover:text-slate-200"
        >
          ✕
        </button>
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
    </div>
  );
}
