import { useState, type ReactNode } from "react";
import { t } from "../lib/i18n";
import type { Arrival, Catalog, Place, RouteSet } from "../lib/types";
import { Remove } from "./Cross";
import { Icon } from "./Icon";
import { SavedPanel } from "./SavedPanel";
import { Timetable } from "./Timetable";

/** Which of the account's lists is shown, or the account itself */
export type MineSection = "stops" | "places" | "sets" | "account";

/** Everything that is the account's own: the pinned stops with what is due
 * there, the saved places and the route sets, one at a time under a switch,
 * with the account itself behind a button beside it. */
export function MinePanel(p: {
  catalog: Catalog;
  arrivals: Record<string, Arrival[]>;
  pins: number[];
  onPins: (next: number[]) => void;
  onStop: (i: number) => void;
  /** The routes picked, by id */
  watching: Set<string>;
  onToggle: (id: string) => void;
  onRoute: (i: number) => void;
  places: Place[];
  onPlaces: (next: Place[]) => void;
  onPlace: (place: Place) => void;
  sets: RouteSet[];
  active: string | null;
  onActivate: (set: RouteSet) => void;
  onDelete: (set: RouteSet) => Promise<void>;
  username: string;
  /** What the account button opens into */
  account: ReactNode;
  /** Held by the page, so the panel reopens on the list it was left on */
  section: MineSection;
  onSection: (next: MineSection) => void;
}) {
  const account = p.section === "account";
  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center gap-1.5">
        {SWITCH.map(([section, label]) => (
          <button
            key={section}
            onClick={() => p.onSection(section)}
            aria-pressed={p.section === section}
            className={`rounded-full px-3 py-1 text-sm ${
              p.section === section ? "bg-accent/15 text-accent" : "text-slate-300 hover:bg-raised/70"
            }`}
          >
            {t[label]}
          </button>
        ))}
        <button
          onClick={() => p.onSection(account ? "stops" : "account")}
          aria-pressed={account}
          aria-label={`${t.account}: ${p.username}`}
          title={`${t.account}: ${p.username}`}
          className={`ml-auto flex min-w-0 items-center gap-1.5 rounded-full px-2 py-1 text-sm ${
            account ? "bg-accent/15 text-accent" : "text-slate-400 hover:bg-raised/70"
          }`}
        >
          <Icon name="account" className="size-4 shrink-0" />
          <span className="truncate">{p.username}</span>
        </button>
      </div>
      {p.section === "stops" && (
        <Timetable
          catalog={p.catalog}
          stops={p.pins}
          arrivals={p.arrivals}
          onPins={p.onPins}
          onStop={p.onStop}
          watching={p.watching}
          onToggle={p.onToggle}
          onRoute={p.onRoute}
        />
      )}
      {p.section === "places" && (
        <SavedPanel places={p.places} onPlaces={p.onPlaces} onPlace={p.onPlace} />
      )}
      {p.section === "sets" && (
        <SetList sets={p.sets} active={p.active} onActivate={p.onActivate} onDelete={p.onDelete} />
      )}
      {account && p.account}
    </div>
  );
}

const SWITCH = [
  ["stops", "mineStops"],
  ["places", "minePlaces"],
  ["sets", "sets"],
] as const;

/** A set is chosen here, or deleted; what it holds is changed where routes are
 * watched */
function SetList({
  sets,
  active,
  onActivate,
  onDelete,
}: {
  sets: RouteSet[];
  active: string | null;
  onActivate: (set: RouteSet) => void;
  onDelete: (set: RouteSet) => Promise<void>;
}) {
  const [error, setError] = useState("");
  if (sets.length === 0) return <p className="text-sm text-slate-500">{t.noSets}</p>;
  return (
    <>
      <ul className="space-y-1">
        {sets.map((s) => (
          <li key={s.id} className="flex items-center gap-1">
            <button
              onClick={() => onActivate(s)}
              aria-pressed={s.id === active}
              className={`min-w-0 flex-1 truncate rounded-md px-2 py-1.5 text-left text-sm ${
                s.id === active ? "bg-accent/15 text-accent" : "text-slate-300 hover:bg-raised/70"
              }`}
            >
              {s.name}
              <span className="ml-2 text-xs text-slate-500">{s.routes.length}</span>
            </button>
            <Remove
              title={t.deleteSet}
              onClick={() => {
                setError("");
                onDelete(s).catch((err: unknown) =>
                  setError(err instanceof Error ? err.message : t.failed),
                );
              }}
            />
          </li>
        ))}
      </ul>
      {error && <p className="mt-1 text-xs text-rose-400">{error}</p>}
    </>
  );
}
