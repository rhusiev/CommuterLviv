import { useCallback, useEffect, useMemo, useState } from "react";
import { MapCanvas } from "./components/MapCanvas";
import { RoutePanel } from "./components/RoutePanel";
import { SignIn } from "./components/SignIn";
import { JourneyPanel, type Point } from "./components/JourneyPanel";
import { StopCard } from "./components/StopCard";
import { StopSearch } from "./components/StopSearch";
import { VehicleCard } from "./components/VehicleCard";
import { Timetable } from "./components/Timetable";
import { api, ApiError, catalog as fetchCatalog } from "./lib/api";
import { loadTheme, saveTheme, type Theme } from "./lib/theme";
import { readUrl, writeUrl } from "./lib/url";
import { useLive } from "./lib/useLive";
import type { Catalog, Me, RouteSet } from "./lib/types";
import { t } from "./lib/i18n";

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
  const [veh, setVeh] = useState<number | null>(null);
  const [focus, setFocus] = useState<{ lat: number; lon: number } | null>(null);
  const [tab, setTab] = useState<"map" | "times" | "plan">(opened.tab);
  const [from, setFrom] = useState<Point | null>(null);
  const [to, setTo] = useState<Point | null>(null);
  const [picking, setPicking] = useState<"from" | "to" | null>(null);
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
    setNotice(err instanceof Error ? err.message : t.noService);
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

  /** The journey's two ends on the map. Lettered rather than coloured: two pins
   * of the same shape are told apart by the letter on a map of any palette */
  const marks = useMemo(() => {
    const out: { lat: number; lon: number; label: string }[] = [];
    if (from) out.push({ ...from, label: "A" });
    if (to) out.push({ ...to, label: "B" });
    return out;
  }, [from, to]);

  /** Where the browser says the phone is, for either end of the journey. The
   * map has its own locate button and its own fix; this asks separately rather
   * than reaching into it, because the two are wanted at different moments and
   * a refusal here should not turn the map's dot off. */
  const useHere = (which: "from" | "to") => {
    navigator.geolocation?.getCurrentPosition(
      (pos) => {
        const at = { lat: pos.coords.latitude, lon: pos.coords.longitude };
        (which === "from" ? setFrom : setTo)(at);
      },
      () => setNotice(t.noLocation),
      { enableHighAccuracy: true, timeout: 10_000 },
    );
  };

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
      <Splash text={t.waiting} />
    ) : (
      <Splash text={notice} onRetry={() => void load()} />
    );
  if (me === null) return <SignIn code={null} onIn={() => void load()} />;
  if (!cat)
    return notice === null ? (
      <Splash text={t.loading} />
    ) : (
      <Splash text={notice} onRetry={loadCatalog} />
    );

  return (
    // The map is the window and nothing is docked to an edge: the bar, the tab
    // switcher, the drawers and the cards are all rounded surfaces floating over
    // it, which is why they carry their own inset rather than taking space from
    // it. `pointer-events-none` on the strips that only position things keeps
    // the gaps between them draggable map
    <div className="relative h-dvh overflow-hidden bg-plate text-slate-100">
      {/* Mounted whatever the tab is, and never hidden: the timetable and the
          planner float over the city rather than replacing it, and a map that
          is unmounted and remounted is a second style download */}
      <MapCanvas
        catalog={cat}
        live={live}
        stops={stops}
        selected={stop}
        onPickStop={(i) => {
          setStop(i);
          if (i !== null) setVeh(null);
        }}
        vehicle={veh}
        onPickVehicle={setVeh}
        focus={focus}
        picking={picking !== null}
        onPickPoint={(lat, lon) => {
          if (picking === "from") setFrom({ lat, lon });
          if (picking === "to") setTo({ lat, lon });
          setPicking(null);
        }}
        marks={marks}
        theme={theme}
      />

      <header className="pointer-events-none absolute inset-x-0 top-0 z-30 flex items-start gap-2 p-3">
        <button
          onClick={() => setPanel((v) => !v)}
          title={t.routes}
          aria-label={t.routes}
          className={`fab pointer-events-auto ${
            panel ? "text-accent" : "text-slate-300 hover:text-slate-100"
          }`}
        >
          <svg viewBox="0 0 24 24" className="size-5" fill="none" stroke="currentColor" strokeWidth="2">
            <path d="M4 7h16M4 12h16M4 17h16" strokeLinecap="round" />
          </svg>
        </button>
        <div className="pointer-events-auto min-w-0 flex-1 sm:max-w-sm">
          <StopSearch
            catalog={cat}
            onGo={(i) => {
              const s = cat.stops[i]!;
              setTab("map");
              setStop(i);
              setFocus({ lat: s.lat, lon: s.lon });
            }}
          />
        </div>
        <span
          className="bar pointer-events-auto ml-auto flex h-10 items-center gap-2 px-3.5 text-xs text-slate-400"
          title={connection}
        >
          <span
            className={`size-2 rounded-full ${
              connection === "live" ? "bg-emerald-500" : "bg-amber-500"
            }`}
          />
          {t.vehicles(count)}
        </span>
      </header>

      {notice !== null && (
        <p className="panel absolute left-1/2 top-19 z-40 flex max-w-[calc(100vw-1.5rem)] -translate-x-1/2 items-center gap-2 px-3 py-2 text-sm text-rose-200">
          {notice}
          <button onClick={() => setNotice(null)} className="text-rose-400 hover:text-rose-200">
            ✕
          </button>
        </p>
      )}

      {tab === "plan" && (
        <aside className="panel absolute right-3 top-19 bottom-20 z-20 w-96 max-w-[calc(100vw-1.5rem)] overflow-y-auto p-3">
          <JourneyPanel
            catalog={cat}
            from={from}
            to={to}
            picking={picking}
            onPick={setPicking}
            onSwap={() => {
              setFrom(to);
              setTo(from);
            }}
            onHere={useHere}
            onStop={(i) => {
              setTab("map");
              setStop(i);
              setFocus({ lat: cat.stops[i]!.lat, lon: cat.stops[i]!.lon });
            }}
          />
        </aside>
      )}

      {tab === "times" && (
        <section className="panel absolute inset-x-3 top-19 bottom-20 z-20 mx-auto max-w-lg overflow-hidden">
          <Timetable
            catalog={cat}
            stops={pins}
            arrivals={live.arrivals}
            onUnpin={(i) => setPinned(pins.filter((p) => p !== i))}
          />
        </section>
      )}

      {tab === "map" && veh !== null && stop === null && (
        <div className="pointer-events-none absolute inset-x-3 bottom-20 z-10 mx-auto max-w-md">
          <VehicleCard
            catalog={cat}
            veh={veh}
            onStop={(i) => {
              setStop(i);
              setVeh(null);
            }}
            onClose={() => setVeh(null)}
          />
        </div>
      )}

      {tab === "map" && stop !== null && (
        <div className="pointer-events-none absolute inset-x-3 bottom-20 z-10 mx-auto max-w-md">
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

      {/* Centred at the bottom, where a thumb is, rather than in the bar: it is
          the one control used at any moment and the only one worth that spot */}
      <nav className="bar absolute bottom-3 left-1/2 z-30 flex -translate-x-1/2 gap-1 p-1 text-sm">
        {(["map", "times", "plan"] as const).map((v) => (
          <button
            key={v}
            onClick={() => setTab(v)}
            className={`rounded-full px-4 py-1.5 transition-colors ${
              tab === v
                ? "bg-accent/15 font-medium text-accent"
                : "text-slate-400 hover:text-slate-200"
            }`}
          >
            {v === "map" ? t.map : v === "times" ? t.times : t.plan}
          </button>
        ))}
      </nav>

      {panel && (
        <aside className="panel absolute left-3 top-19 bottom-20 z-20 w-80 max-w-[calc(100vw-1.5rem)] p-3">
          <RoutePanel
            catalog={cat}
            username={me.username}
            onOut={async () => {
              // Signed out here whether or not the request landed: the session
              // it is ending may already be the reason it failed
              await api.logout().catch(() => undefined);
              setMe(null);
            }}
            theme={theme}
            onTheme={(next) => {
              setTheme(next);
              saveTheme(next);
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
    </div>
  );
}

function Splash({ text, onRetry }: { text: string; onRetry?: () => void }) {
  return (
    <div className="flex min-h-dvh flex-col items-center justify-center gap-3 bg-plate text-slate-500">
      <p className="max-w-sm px-4 text-center">{text}</p>
      {onRetry && (
        <button onClick={onRetry} className="btn-quiet">
          {t.tryAgain}
        </button>
      )}
    </div>
  );
}
