import { useState, type ReactNode } from "react";
import { t } from "../lib/i18n";
import type { Arrival, Catalog, Place, RouteSet } from "../lib/types";
import { Remove } from "./Cross";
import { Icon } from "./Icon";
import { SavedPanel } from "./SavedPanel";
import { Timetable } from "./Timetable";

/** Everything that is the account's own, in one list: the pinned stops with
 * what is due there, the saved places, the route sets, and last the account
 * itself, folded until it is wanted. */
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
  /** What the account row opens into */
  account: ReactNode;
}) {
  const [open, setOpen] = useState(false);
  return (
    <div className="flex flex-col gap-4">
      <Section title={t.pinnedStops}>
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
      </Section>
      <Section title={t.places}>
        <SavedPanel places={p.places} onPlaces={p.onPlaces} onPlace={p.onPlace} />
      </Section>
      <Section title={t.sets}>
        <SetList sets={p.sets} active={p.active} onActivate={p.onActivate} onDelete={p.onDelete} />
      </Section>
      <section className="border-t border-hair pt-3">
        <button
          onClick={() => setOpen((v) => !v)}
          aria-expanded={open}
          className="flex w-full items-center gap-2 rounded-md px-2 py-2 text-left text-sm text-slate-300 hover:bg-raised/70"
        >
          <Icon name="account" className="size-4" />
          <span>{t.account}</span>
          <span className="min-w-0 flex-1 truncate text-slate-500">{p.username}</span>
          <Icon name={open ? "up" : "down"} className="size-4 text-slate-500" />
        </button>
        {open && <div className="mt-1">{p.account}</div>}
      </section>
    </div>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section>
      <h2 className="mb-2 text-xs uppercase tracking-wide text-slate-500">{title}</h2>
      {children}
    </section>
  );
}

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
