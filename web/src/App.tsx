import { useCallback, useEffect, useMemo, useState } from "react";
import { MapCanvas } from "./components/MapCanvas";
import { RoutePanel } from "./components/RoutePanel";
import { SignIn } from "./components/SignIn";
import { StopCard } from "./components/StopCard";
import { StopSearch } from "./components/StopSearch";
import { Timetable } from "./components/Timetable";
import { api, ApiError, catalog as fetchCatalog } from "./lib/api";
import { loadTheme, saveTheme, type Theme } from "./lib/theme";
import { readUrl, writeUrl } from "./lib/url";
import { useLive } from "./lib/useLive";
import type { Catalog, Me, RouteSet } from "./lib/types";

const JOIN = /^\/join\/([\w-]+)\/?$/;

/** Where pins used to live, before the server kept them. Read once per account
 * to carry them over, then deleted. The numbers in it are catalog positions,
 * which is exactly the bug that moved them: they are read against whatever
 * catalog is loaded now, which is the best that can be done for them. */
const oldPinKey = (user: string) => `commuterlviv.pins.${user}`;

export function App() {
  const [me, setMe] = useState<Me | null | undefined>(undefined);
  const [cat, setCat] = useState<Catalog | null>(null);
  // Read once, at mount: from here on this component is what the address bar
  // follows rather than the other way round
  const [opened] = useState(readUrl);
  const [picked, setPicked] = useState<Set<string>>(new Set(opened.routes ?? []));
  const [sets, setSets] = useState<RouteSet[]>([]);
  const [active, setActive] = useState<string | null>(null);
  const [pinIds, setPinIds] = useState<string[]>([]);
  const [stop, setStop] = useState<number | null>(null);
  const [focus, setFocus] = useState<{ lat: number; lon: number } | null>(null);
  const [tab, setTab] = useState<"map" | "times">(opened.tab);
  const [panel, setPanel] = useState(false);
  const [theme, setTheme] = useState<Theme>(loadTheme);
  const [notice, setNotice] = useState<string | null>(null);

  const code = JOIN.exec(location.pathname)?.[1] ?? null;
  // A new set of arrivals changes the store's snapshot, which re-renders this
  // and hands the timetable a fresh `live.arrivals` - nothing here reads the
  // timestamp itself
  const { live, connection, count } = useLive();

  /** Nothing here throws into the void. A signed-out session puts the sign-in
   * screen up, and everything else is said on screen: rethrowing left the
   * splash reading "…" with the reason in a console nobody has open. */
  const failed = useCallback((err: unknown) => {
    if (err instanceof ApiError && err.status === 401) {
      setMe(null);
      return;
    }
    setNotice(err instanceof Error ? err.message : "the service is not answering");
  }, []);

  const load = useCallback(async () => {
    try {
      const who = await api.me();
      setMe(who);
      setSets(who.sets.sets);
      setActive(who.sets.active);
      // A link that names routes is what the person opening it asked for; the
      // account's active set only decides when the link says nothing
      const set = who.sets.sets.find((s) => s.id === who.sets.active);
      if (set && opened.routes === null) setPicked(new Set(set.routes));
      setPinIds(who.sets.pins);
      setNotice(null);
    } catch (err) {
      failed(err);
    }
  }, [failed, opened.routes]);

  useEffect(() => {
    void load();
  }, [load]);

  const loadCatalog = useCallback(() => {
    setNotice(null);
    void fetchCatalog().then(setCat, failed);
  }, [failed]);

  useEffect(() => {
    if (me) loadCatalog();
  }, [me, loadCatalog]);

  const stopIndex = useMemo(() => {
    const m = new Map<string, number>();
    cat?.stops.forEach((s, i) => m.set(s.id, i));
    return m;
  }, [cat]);

  /** The socket and every panel address a stop by its position in the catalog;
   * only what is stored is an id. */
  const pins = useMemo(
    () => pinIds.map((id) => stopIndex.get(id)).filter((i): i is number => i !== undefined),
    [pinIds, stopIndex],
  );

  useEffect(() => {
    if (!cat || !me) return;
    const key = oldPinKey(me.username);
    const held = localStorage.getItem(key);
    if (held === null) return;
    try {
      const ids =
        pinIds.length === 0
          ? (JSON.parse(held) as number[])
              .map((i) => cat.stops[i]?.id)
              .filter((id): id is string => id !== undefined)
          : [];
      if (ids.length === 0) {
        localStorage.removeItem(key);
        return;
      }
      setPinIds(ids);
      // Dropped only once the server has them, so a bad day offline is not
      // what loses somebody's pins
      void api.setPins(ids).then(() => localStorage.removeItem(key));
    } catch {
      // A localStorage value that is not a list of numbers is nobody's pins
      localStorage.removeItem(key);
    }
    // Runs when the catalog arrives, and must not re-run when the pins change
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cat, me]);

  /** The stop a link named, once there is a catalog to look it up in. It flies
   * there, because a link to a stop that leaves the camera over the centre of
   * the city has not shown anybody the stop. */
  useEffect(() => {
    if (!cat || opened.stop === null) return;
    const i = stopIndex.get(opened.stop);
    if (i === undefined) return;
    setStop(i);
    setFocus({ lat: cat.stops[i]!.lat, lon: cat.stops[i]!.lon });
    // Only when the catalog arrives: after that the address bar follows the
    // screen and this would fight it
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cat]);

  useEffect(() => {
    if (!cat) return;
    writeUrl({
      routes: [...picked],
      stop: stop === null ? null : cat.stops[stop]!.id,
      tab,
    });
  }, [cat, picked, stop, tab]);

  const index = useMemo(() => {
    const m = new Map<string, number>();
    cat?.routes.forEach((r, i) => m.set(r.id, i));
    return m;
  }, [cat]);

  const indexes = useMemo(
    () => [...picked].map((id) => index.get(id)).filter((i): i is number => i !== undefined),
    [picked, index],
  );

  useEffect(() => {
    if (cat) live.setRoutes(indexes);
  }, [live, cat, indexes]);

  const watched = useMemo(
    () => (stop === null || pins.includes(stop) ? pins : [...pins, stop]),
    [pins, stop],
  );

  useEffect(() => {
    if (cat) live.setStops(watched);
  }, [live, cat, watched]);

  /** Only the stops of the routes on the map are drawn or clickable: the whole
   * catalog is a thousand circles that mean nothing to someone watching two
   * routes. */
  const stops = useMemo(() => {
    if (!cat) return [];
    const on = new Set(indexes);
    const out: number[] = [];
    cat.stops.forEach((s, i) => {
      if (s.routes.some((r) => on.has(r))) out.push(i);
    });
    return out;
  }, [cat, indexes]);

  const setPinned = (next: number[]) => {
    if (!cat) return;
    const ids = next.map((i) => cat.stops[i]!.id);
    setPinIds(ids);
    // Optimistic: a pin that failed to save comes back at the next sign-in,
    // and blocking the tap on a round trip is worse than that
    void api.setPins(ids).catch(() => undefined);
  };

  const refreshSets = async () => {
    const s = await api.sets();
    setSets(s.sets);
    setActive(s.active);
  };

  if (code !== null && !me) return <SignIn code={code} onIn={() => void load()} />;
  if (me === undefined)
    return notice === null ? (
      <Splash text="…" />
    ) : (
      <Splash text={notice} onRetry={() => void load()} />
    );
  if (me === null) return <SignIn code={null} onIn={() => void load()} />;
  if (!cat)
    return notice === null ? (
      <Splash text="loading the city" />
    ) : (
      <Splash text={notice} onRetry={loadCatalog} />
    );

  return (
    <div className="flex h-dvh flex-col bg-slate-950 text-slate-100">
      <header className="flex items-center gap-2 border-b border-slate-800 px-3 py-2">
        <button
          onClick={() => setPanel((v) => !v)}
          className="rounded-md bg-slate-800 px-3 py-1.5 text-sm hover:bg-slate-700"
        >
          Routes
        </button>
        <nav className="flex rounded-md bg-slate-900 p-0.5 text-sm">
          {(["map", "times"] as const).map((t) => (
            <button
              key={t}
              onClick={() => setTab(t)}
              className={`rounded px-3 py-1 ${tab === t ? "bg-slate-700" : "text-slate-400"}`}
            >
              {t === "map" ? "Map" : "Times"}
            </button>
          ))}
        </nav>
        <StopSearch
          catalog={cat}
          onGo={(i) => {
            const s = cat.stops[i]!;
            setTab("map");
            setStop(i);
            setFocus({ lat: s.lat, lon: s.lon });
          }}
        />
        <span className="ml-auto flex items-center gap-2 text-xs text-slate-500">
          <span
            className={`size-2 rounded-full ${
              connection === "live" ? "bg-emerald-500" : "bg-amber-500"
            }`}
            title={connection}
          />
          {count} vehicles
          <button
            onClick={async () => {
              // Signed out here whether or not the request landed: the session
              // it is ending may already be the reason it failed
              await api.logout().catch(() => undefined);
              setMe(null);
            }}
            className="text-slate-500 hover:text-slate-200"
          >
            {me.username} · out
          </button>
        </span>
      </header>

      {notice !== null && (
        <p className="flex items-center gap-2 bg-rose-950/80 px-3 py-1.5 text-sm text-rose-200">
          {notice}
          <button
            onClick={() => setNotice(null)}
            className="ml-auto text-rose-400 hover:text-rose-200"
          >
            ✕
          </button>
        </p>
      )}

      <main className="relative flex-1 overflow-hidden">
        <div className={tab === "map" ? "absolute inset-0" : "hidden"}>
          <MapCanvas
            catalog={cat}
            live={live}
            stops={stops}
            selected={stop}
            onPickStop={setStop}
            focus={focus}
            theme={theme}
          />
          {stop !== null && (
            <div className="pointer-events-none absolute inset-x-3 bottom-3 z-10 mx-auto max-w-md">
              <StopCard
                catalog={cat}
                stop={stop}
                arrivals={live.arrivals[String(stop)]}
                pinned={pins.includes(stop)}
                onPin={() =>
                  setPinned(pins.includes(stop) ? pins.filter((i) => i !== stop) : [...pins, stop])
                }
                onClose={() => setStop(null)}
              />
            </div>
          )}
        </div>

        {tab === "times" && (
          <Timetable
            catalog={cat}
            stops={pins}
            arrivals={live.arrivals}
            onUnpin={(i) => setPinned(pins.filter((p) => p !== i))}
          />
        )}

        {panel && (
          <aside className="absolute inset-y-0 left-0 z-20 w-80 max-w-[85vw] border-r border-slate-800 bg-slate-950/95 p-3 backdrop-blur">
            <RoutePanel
              catalog={cat}
              theme={theme}
              onTheme={(t) => {
                setTheme(t);
                saveTheme(t);
              }}
              picked={picked}
              onToggle={(id) =>
                setPicked((was) => {
                  const next = new Set(was);
                  if (!next.delete(id)) next.add(id);
                  return next;
                })
              }
              onClear={() => setPicked(new Set())}
              sets={sets}
              active={active}
              onActivate={(s) => {
                setPicked(new Set(s.routes));
                setActive(s.id);
                void api.activateSet(s.id).catch(failed);
              }}
              onCreate={async (name) => {
                await api.createSet(name, [...picked]);
                await refreshSets();
              }}
              onUpdate={async (s) => {
                await api.updateSet(s.id, s.name, [...picked]);
                await refreshSets();
              }}
              onDelete={async (s) => {
                await api.deleteSet(s.id);
                await refreshSets();
              }}
            />
          </aside>
        )}
      </main>
    </div>
  );
}

function Splash({ text, onRetry }: { text: string; onRetry?: () => void }) {
  return (
    <div className="flex min-h-dvh flex-col items-center justify-center gap-3 bg-slate-950 text-slate-500">
      <p className="max-w-sm px-4 text-center">{text}</p>
      {onRetry && (
        <button
          onClick={onRetry}
          className="rounded-md bg-slate-800 px-3 py-1.5 text-sm text-slate-200 hover:bg-slate-700"
        >
          try again
        </button>
      )}
    </div>
  );
}
