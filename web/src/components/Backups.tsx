import { useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { clock } from "../lib/eta";
import { t } from "../lib/i18n";
import { shortlist, type Prefer } from "../lib/prefer";
import { Icon } from "./Icon";
import { RouteBadge } from "./RouteBadge";
import type { Catalog, Journey, Leg } from "../lib/types";

type Chain = { route: number; dep: number; a: number; planned?: boolean }[];

/** The `n`-th backup of the journey's `leg`-th leg, or null for the journey
 *  itself */
export type WayPick = { leg: number; n: number } | null;

/** Each ride of a journey with the other ways to the door from where it
 *  boards, over everything else. Its clicks stay out of the card it opens
 *  from, which would toggle */
export function Backups({
  journey,
  prefer,
  place,
  catalog,
  onWay,
  onClose,
}: {
  journey: Journey;
  prefer: Prefer;
  /** Where the plan's option of that index is listed, from 1 */
  place: (option: number) => number;
  catalog: Catalog;
  /** Draws the way picked on the map, failing with what went wrong */
  onWay: (pick: WayPick) => Promise<void>;
  onClose: () => void;
}) {
  const [pending, setPending] = useState(false);
  const [failed, setFailed] = useState<string | null>(null);
  const pick = async (which: WayPick) => {
    setPending(true);
    setFailed(null);
    try {
      await onWay(which);
      onClose();
    } catch (err) {
      setFailed(err instanceof Error ? err.message : t.failed);
    } finally {
      setPending(false);
    }
  };
  const rides = journey.legs.filter((leg) => leg.kind === "ride" && leg.route !== undefined);
  const way = (chain: Chain, arr: number, which: WayPick, option = -1) => (
    <button
      key={chain.map((r) => `${r.route} ${r.dep}`).join()}
      onClick={() => void pick(which)}
      disabled={pending}
      title={t.showWay}
      className={`block w-full rounded px-1 py-1 text-left disabled:opacity-50 ${which === null ? "bg-accent/15" : ""}`}
    >
      <span className="flex items-center gap-1">
        <span className="w-12 shrink-0 tabular-nums text-slate-400">{clock(chain[0]!.dep)}</span>
        <span className="flex min-w-0 flex-1 flex-wrap items-center gap-1">
          {chain.map((r, i) => (
            <span key={i} className="flex items-center gap-1">
              {i > 0 && <Icon name="right" className="size-3 text-slate-500" />}
              {catalog.routes[r.route] && (
                <RouteBadge route={catalog.routes[r.route]!} outline={r.planned} className="px-1.5 text-xs" />
              )}
            </span>
          ))}
        </span>
        {option >= 0 && (
          <span title={t.alsoOptionHint} className="shrink-0 rounded bg-raised px-1 text-xs text-slate-400">
            {t.alsoOption(place(option))}
          </span>
        )}
        <span className="flex shrink-0 items-center gap-0.5 tabular-nums text-slate-200">
          <Icon name="destination" className="size-3.5 text-slate-400" />
          {clock(arr)}
        </span>
      </span>
      {chain.length > 1 && (
        <span className="block pl-12 text-xs text-slate-500">
          {t.changeAt(chain.slice(1).map((r) => catalog.stops[r.a]?.name ?? "").join(", "))}
        </span>
      )}
    </button>
  );
  // To the body: the panel's backdrop blur would otherwise hold a fixed overlay inside it
  return createPortal(
    <div
      onClick={(e) => {
        e.stopPropagation();
        onClose();
      }}
      className="fixed inset-0 z-40 flex cursor-default items-center justify-center bg-black/50 p-4"
    >
      <div onClick={(e) => e.stopPropagation()} className="panel max-h-full w-96 max-w-full overflow-y-auto p-4 text-sm">
        <h2 className="font-medium">{t.backups}</h2>
        <p className="mt-1 text-xs text-slate-400">{t.backupsWhy}</p>
        {failed && <p className="mt-2 text-xs text-rose-300">{failed}</p>}
        {rides.map((leg, i) => (
          <div key={i} className="mt-3 border-t border-hair pt-2">
            <h3 className="mb-1 truncate text-slate-200">{catalog.stops[leg.a]?.name}</h3>
            {way(
              rides.slice(i).map((r) => ({ route: r.route!, dep: r.dep, a: r.a })),
              journey.arr,
              null,
            )}
            <Ways leg={leg} at={journey.legs.indexOf(leg)} prefer={prefer} way={way} />
          </div>
        ))}
        <button onClick={onClose} className="btn-quiet mt-3 ml-auto block">
          {t.ok}
        </button>
      </div>
    </div>,
    document.body,
  );
}

/** A ride's backups, the shortlist by what is preferred until asked for all */
function Ways({
  leg,
  at,
  prefer,
  way,
}: {
  leg: Leg;
  /** The leg's place in its journey */
  at: number;
  prefer: Prefer;
  way: (chain: Chain, arr: number, which: WayPick, option?: number) => ReactNode;
}) {
  const [all, setAll] = useState(false);
  const backups = leg.backups ?? [];
  if (!backups.length) return <p className="px-1 py-1 text-xs text-slate-500">{t.noBackup}</p>;
  const shown = all ? backups : shortlist(backups, prefer);
  return (
    <>
      {shown.map((b) => way(b.rides, b.arr, { leg: at, n: backups.indexOf(b) }, b.option))}
      {shown.length < backups.length && (
        <button onClick={() => setAll(true)} className="px-1 py-1 text-xs text-accent">
          {t.moreBackups(backups.length - shown.length)}
        </button>
      )}
    </>
  );
}
