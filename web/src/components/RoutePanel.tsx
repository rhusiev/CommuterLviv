import { useMemo, useState } from "react";
import type { Catalog, Route, RouteSet } from "../lib/types";
import { t } from "../lib/i18n";
import { RouteBadge } from "./RouteBadge";
import { Icon } from "./Icon";
import { Remove } from "./Cross";

/** Which routes are tracked, and the saved sets of them - nothing else. What
 * the map draws lives in the layers panel, and the account in its own menu.
 *
 * A set is the selection at the moment it was saved: editing the selection
 * does not touch it until it is saved again. */

type Props = {
  catalog: Catalog;
  picked: Set<string>;
  onToggle: (id: string) => void;
  onClear: () => void;
  /** A click here already toggles the route, so this is on `onContextMenu` */
  onRoute: (i: number) => void;
  sets: RouteSet[];
  active: string | null;
  onActivate: (set: RouteSet) => void;
  onCreate: (name: string) => Promise<void>;
  onUpdate: (set: RouteSet) => Promise<void>;
  onDelete: (set: RouteSet) => Promise<void>;
};

export function RoutePanel(p: Props) {
  const [query, setQuery] = useState("");
  const [name, setName] = useState("");
  const [error, setError] = useState("");

  // Grouped by vehicle type, in catalog order: tram 1 and bus 1 are
  // different lines that would otherwise sit in one undivided grid
  const groups = useMemo(() => {
    const q = query.trim().toLowerCase();
    const out = new Map<string, (readonly [Route, number])[]>();
    p.catalog.routes.forEach((r, i) => {
      if (q && !r.short.toLowerCase().includes(q) && !r.long.toLowerCase().includes(q))
        return;
      out.set(r.type, [...(out.get(r.type) ?? []), [r, i] as const]);
    });
    return [...out];
  }, [p.catalog, query]);

  const guard = (fn: () => Promise<void>) => async () => {
    setError("");
    try {
      await fn();
    } catch (err) {
      setError(err instanceof Error ? err.message : t.failed);
    }
  };

  return (
    <div className="flex h-full flex-col gap-3 overflow-hidden">
      <section>
        <h2 className="text-xs uppercase tracking-wide text-slate-500">{t.sets}</h2>
        <ul className="mt-2 space-y-1">
          {p.sets.map((s) => (
            <li key={s.id} className="flex items-center gap-1">
              <button
                onClick={() => p.onActivate(s)}
                className={`flex-1 truncate rounded-md px-2 py-1.5 text-left text-sm ${
                  s.id === p.active
                    ? "bg-accent/15 text-accent"
                    : "text-slate-300 hover:bg-raised/70"
                }`}
              >
                {s.name}
                <span className="ml-2 text-xs text-slate-500">{s.routes.length}</span>
              </button>
              <button
                title={t.saveSet}
                onClick={guard(() => p.onUpdate(s))}
                className="rounded-control px-2 py-1.5 text-slate-500 transition-colors hover:bg-raised/70 hover:text-slate-200"
              >
                <Icon name="check" className="size-4" />
              </button>
              <Remove title={t.deleteSet} onClick={guard(() => p.onDelete(s))} />
            </li>
          ))}
        </ul>
        <form
          className="mt-2 flex gap-1"
          onSubmit={(e) => {
            e.preventDefault();
            if (!name.trim()) return;
            void guard(async () => {
              await p.onCreate(name.trim());
              setName("");
            })();
          }}
        >
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder={t.newSet}
            className="field min-w-0 flex-1 py-1.5"
          />
          <button className="btn-quiet px-2 py-0" title={t.add}>
            <Icon name="plus" className="size-4" />
          </button>
        </form>
        {error && <p className="mt-1 text-xs text-rose-400">{error}</p>}
      </section>

      <section className="flex min-h-0 flex-1 flex-col">
        <div className="flex min-h-5 items-center justify-between">
          <h2 className="text-xs uppercase tracking-wide text-slate-500">
            {t.routes}
            <span className="ml-2 normal-case text-slate-600">{t.on(p.picked.size)}</span>
          </h2>
          {p.picked.size > 0 && (
            <button onClick={p.onClear} title={t.clear} className="text-slate-500 hover:text-slate-300">
              <Icon name="clear" className="size-4" />
            </button>
          )}
        </div>
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder={t.filter}
          className="field mt-2 py-1.5"
        />
        <div data-chips className="mt-2 min-h-0 space-y-2 overflow-y-auto">
          {groups.map(([type, routes]) => (
            <div key={type}>
              <h3 className="mb-1 text-xs text-slate-500">{t.kinds[type] ?? type}</h3>
              {/* Columns, so a chip wider than the rest does not shift the ones after it */}
              <div className="grid grid-cols-[repeat(auto-fill,minmax(4rem,1fr))] gap-1">
                {routes.map(([r, i]) => {
                  const on = p.picked.has(r.id);
                  return (
                    <button
                      key={r.id}
                      onClick={() => p.onToggle(r.id)}
                      // `onContextMenu` covers both right-click and touch long-press
                      onContextMenu={(e) => {
                        e.preventDefault();
                        p.onRoute(i);
                      }}
                    >
                      <RouteBadge
                        route={r}
                        muted={!on}
                        className={`w-full px-2 py-1 text-sm ${
                          on ? "" : "bg-raised/70 text-slate-400 hover:bg-raised"
                        }`}
                      />
                    </button>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
        <p className="mt-1.5 text-xs text-slate-500">{t.holdForLine}</p>
      </section>
    </div>
  );
}
