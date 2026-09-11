import { useMemo, useState } from "react";
import { THEMES, type Theme } from "../lib/theme";
import type { Catalog, RouteSet } from "../lib/types";
import { lang, setLang, t } from "../lib/i18n";
import { RouteBadge } from "./RouteBadge";

/** Which routes are on the map, and the named sets that stand for a selection:
 * one for the way to work, one for home. A set is the selection at the moment
 * it was saved - editing the selection does not touch it until it is saved.
 *
 * The drawer is also where the account, the language and the basemap live.
 * Nothing above the map is a settings bar any more, so everything that is set
 * once and then left alone is behind the one button that opens this. */

type Props = {
  catalog: Catalog;
  username: string;
  onOut: () => void;
  theme: Theme;
  onTheme: (theme: Theme) => void;
  picked: Set<string>;
  onToggle: (id: string) => void;
  onClear: () => void;
  /** A route's line. A click here already means show it on the map, which is
   * what this panel is for, so the line is on the secondary press instead */
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

  const shown = useMemo(() => {
    const q = query.trim().toLowerCase();
    const all = p.catalog.routes.map((r, i) => [r, i] as const);
    if (!q) return all;
    return all.filter(
      ([r]) => r.short.toLowerCase().includes(q) || r.long.toLowerCase().includes(q),
    );
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
      <div className="flex items-baseline gap-2">
        <span className="truncate text-sm font-medium text-slate-200">{p.username}</span>
        <button onClick={p.onOut} className="ml-auto text-xs text-slate-500 hover:text-slate-200">
          {t.out}
        </button>
      </div>

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
                className="rounded-control px-2 py-1.5 text-xs text-slate-500 transition-colors hover:bg-raised/70 hover:text-slate-200"
              >
                {t.save}
              </button>
              <button
                title={t.deleteSet}
                onClick={guard(() => p.onDelete(s))}
                className="rounded-control px-2 py-1.5 text-xs text-slate-500 transition-colors hover:bg-raised/70 hover:text-rose-300"
              >
                ✕
              </button>
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
          <button className="btn-quiet px-3 py-0">
            {t.add}
          </button>
        </form>
        {error && <p className="mt-1 text-xs text-rose-400">{error}</p>}
      </section>

      <section className="flex min-h-0 flex-1 flex-col">
        <div className="flex items-baseline justify-between">
          <h2 className="text-xs uppercase tracking-wide text-slate-500">
            {t.routes}
            <span className="ml-2 normal-case text-slate-600">{t.on(p.picked.size)}</span>
          </h2>
          <button onClick={p.onClear} className="text-xs text-slate-500 hover:text-slate-300">
            {t.clear}
          </button>
        </div>
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder={t.filter}
          className="field mt-2 py-1.5"
        />
        <div data-chips className="mt-2 flex flex-wrap content-start gap-1 overflow-y-auto">
          {shown.map(([r, i]) => {
            const on = p.picked.has(r.id);
            return (
              <button
                key={r.id}
                onClick={() => p.onToggle(r.id)}
                onContextMenu={(e) => {
                  e.preventDefault();
                  p.onRoute(i);
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
        {/* Everywhere else a badge is the way to the line. Here a click is
            already taken, by the one thing this list exists to do */}
        <p className="mt-1.5 text-xs text-slate-500">{t.holdForLine}</p>
      </section>

      <section>
        <h2 className="text-xs uppercase tracking-wide text-slate-500">{t.language}</h2>
        <div className="mt-2 flex gap-1">
          {(["uk", "en"] as const).map((l) => (
            <button
              key={l}
              onClick={() => setLang(l)}
              className={`rounded-md px-2 py-1 text-xs ${
                l === lang
                  ? "bg-accent/15 text-accent"
                  : "bg-raised/70 text-slate-400 hover:bg-raised"
              }`}
            >
              {l === "uk" ? "Українська" : "English"}
            </button>
          ))}
        </div>
      </section>

      <section>
        <h2 className="text-xs uppercase tracking-wide text-slate-500">{t.basemap}</h2>
        <div className="mt-2 flex flex-wrap gap-1">
          {THEMES.map((m) => (
            <button
              key={m.id}
              onClick={() => p.onTheme(m)}
              className={`rounded-md px-2 py-1 text-xs ${
                m.id === p.theme.id
                  ? "bg-accent/15 text-accent"
                  : "bg-raised/70 text-slate-400 hover:bg-raised"
              }`}
            >
              {m.name}
            </button>
          ))}
        </div>
      </section>
    </div>
  );
}
