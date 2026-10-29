import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Banner } from "./components/Banner";
import { MapCanvas } from "./components/MapCanvas";
import { LineView, LinesBrowse } from "./components/LinesPanel";
import { SignIn } from "./components/SignIn";
import { FollowCard } from "./components/FollowCard";
import { JourneyPanel } from "./components/JourneyPanel";
import { StopCard } from "./components/StopCard";
import { HoldMenu, type Held } from "./components/HoldMenu";
import { Confirm } from "./components/Confirm";
import { PlaceCard } from "./components/PlaceCard";
import { AccountSettings } from "./components/AccountSettings";
import { MinePanel, type MineSection } from "./components/MinePanel";
import { LayersPanel } from "./components/LayersPanel";
import { Menu } from "./components/Menu";
import { StopSearch } from "./components/StopSearch";
import { VehicleCard } from "./components/VehicleCard";
import { api, catalog as fetchCatalog, catalogTag } from "./lib/api";
import { pointLabel, useIndex, usePositions } from "./lib/catalog";
import { replaces, samePlace, saved, type Shown } from "./lib/places";
import { loadFlag, loadTheme, saveFlag, saveTheme, type Theme } from "./lib/theme";
import { RAMP, useTraffic } from "./lib/traffic";
import { directions, loadRecent, opened as openedLately, saveRecent } from "./lib/lines";
import { readUrl, TABS, writeUrl, type UrlState } from "./lib/url";
import { heldFollowed, holdFollowed, type Followed } from "./lib/followed";
import { useFollow } from "./lib/useFollow";
import { takeRenewed, useLive } from "./lib/useLive";
import { useMapLayers } from "./lib/useMapLayers";
import { usePlanner } from "./lib/usePlanner";
import { useSession } from "./lib/useSession";
import { walkingFrom } from "./lib/legs";
import type { Catalog, Journey, Me, Place } from "./lib/types";
import { t } from "./lib/i18n";

const LINES_KEY = "commuterlviv.lines";
const TRAFFIC_KEY = "commuterlviv.traffic";
/** Set when the blur is turned off: blurring is the default */
const NO_BLUR_KEY = "commuterlviv.noBlur";
const LOW_FLOOR_KEY = "commuterlviv.lowFloor";
const JOIN = /^\/join\/([\w-]+)\/?$/;
/** A dot in the planner's A/B ring: a place, but neither end of a journey */
const PLACE_MARK = "•";
/** The socket's cap on the stops it is asked to watch (`MAX_STOPS` in hub.py) */
const MAX_WATCHED = 64;

/** Pins from before the server kept them, as catalog positions. Read once per
 * account against whatever catalog is loaded now, then deleted. */
const oldPinKey = (user: string) => `commuterlviv.pins.${user}`;

/** The old pins of `who` as ids of `cat`'s stops, sent to the server, which
 * forgets them locally once it has them. None once the account has pins of its
 * own. */
function carryOldPins(cat: Catalog, who: Me): string[] {
  const key = oldPinKey(who.username);
  const held = localStorage.getItem(key);
  if (held === null) return [];
  try {
    const ids =
      who.sets.pins.length === 0
        ? (JSON.parse(held) as number[])
            .map((i) => cat.stops[i]?.id)
            .filter((id): id is string => id !== undefined)
        : [];
    if (ids.length === 0) {
      localStorage.removeItem(key);
      return [];
    }
    // Dropped only once the server has them
    void api.setPins(ids).then(() => localStorage.removeItem(key));
    return ids;
  } catch {
    localStorage.removeItem(key);
    return [];
  }
}

const TAB_NAMES: Record<UrlState["tab"], string> = {
  map: t.map,
  lines: t.lines,
  plan: t.plan,
  mine: t.mine,
};

export function App() {
  // Read once, at mount: from here on the address bar follows this component
  const [opened] = useState(readUrl);
  const session = useSession(opened.routes);
  const { me, failed, notice, setNotice, picked, places, keepPlaces } = session;
  const [cat, setCat] = useState<Catalog | null>(null);
  const [stop, setStop] = useState<number | null>(null);
  const [veh, setVeh] = useState<number | null>(null);
  /** Picked by name, so it gets a card and a mark of its own */
  const [place, setPlace] = useState<Shown | null>(null);
  /** Where the map was last held, while its menu is open */
  const [held, setHeld] = useState<Held | null>(null);
  /** A save waiting for the answer to whether it may replace the place of its name */
  const [replacing, setReplacing] = useState<Place | null>(null);
  /** A point to list the stops near in the search; a new object lists them again */
  const [around, setAround] = useState<{ lat: number; lon: number } | null>(null);
  const [focus, setFocus] = useState<{ lat: number; lon: number } | null>(null);
  const [tab, setTab] = useState<UrlState["tab"]>(opened.tab);
  const [mineSection, setMineSection] = useState<MineSection>("stops");
  /** The line open in the Lines tab, and which way along it is shown */
  const [route, setRoute] = useState<number | null>(null);
  const [way, setWay] = useState(0);
  const [recent, setRecent] = useState(loadRecent);
  const [allLines, setAllLines] = useState(() => loadFlag(LINES_KEY));
  const planner = usePlanner(tab === "plan", (why) => setNotice(t.noFix[why]));
  const [journey, setJourney] = useState<Journey | null>(null);
  /** Being travelled: it keeps the map, whichever tab is open, and a reload */
  const [followed, setFollowed] = useState<Followed | null>(null);
  const following = followed?.journey ?? null;
  const [folded, setFolded] = useState(false);
  /** The planner's or the lines' panel, whichever tab has it open over the map */
  const panel = useRef<HTMLElement>(null);
  const [theme, setTheme] = useState<Theme>(loadTheme);
  /** Not a failure: news worth a line, such as the city changing */
  const [info, setInfo] = useState<string | null>(null);
  /** The quiet banner closed; it comes back the next time the vehicles go quiet */
  const [quietShut, setQuietShut] = useState(false);
  const [jams, setJams] = useState(() => loadFlag(TRAFFIC_KEY));
  const [noBlur, setNoBlur] = useState(() => loadFlag(NO_BLUR_KEY));
  const [lowFloor, setLowFloor] = useState(() => loadFlag(LOW_FLOOR_KEY));
  /** The vehicle the map keeps in the middle, while its card is open */
  const [tracked, setTracked] = useState<number | null>(null);
  useEffect(() => {
    document.documentElement.classList.toggle("no-blur", noBlur);
  }, [noBlur]);
  const [layersOpen, setLayersOpen] = useState(false);
  const [lineFolded, setLineFolded] = useState(false);

  const openTab = (next: UrlState["tab"]) => {
    setTab(next);
    if (next !== "plan") planner.leave();
  };

  const code = JOIN.exec(location.pathname)?.[1] ?? null;
  const { live, connection, count, quiet } = useLive();
  if (!quiet && quietShut) setQuietShut(false);
  // Asked for again every minute, and only while the view is open
  const traffic = useTraffic(jams);

  /** The catalog, and everything that waited for it: where the address pointed,
   * the journey followed before the page loaded and the pins from before the
   * server kept them */
  const { showPins } = session;
  const loadCatalog = useCallback(
    (who: Me) =>
      fetchCatalog().then((got) => {
        setCat(got);
        if (takeRenewed()) setInfo(t.renewed);
        const tag = catalogTag();
        const held = tag ? heldFollowed(tag, Date.now() / 1000) : null;
        if (held) setFollowed(held);
        if (opened.route !== null) {
          const i = got.routes.findIndex((r) => r.id === opened.route);
          if (i >= 0) setRoute(i);
        }
        const i = got.stops.findIndex((x) => x.id === opened.stop);
        if (i >= 0) {
          setStop(i);
          setFocus({ lat: got.stops[i]!.lat, lon: got.stops[i]!.lon });
        }
        const old = carryOldPins(got, who);
        if (old.length > 0) showPins(old);
      }, failed),
    [failed, opened, showPins],
  );

  useEffect(() => {
    if (me) void loadCatalog(me);
  }, [me, loadCatalog]);

  const stopIndex = useIndex(cat?.stops);

  /** The socket and every panel address a stop by catalog position; only what
   * is stored is an id. */
  const pins = usePositions(stopIndex, session.pinIds);

  useEffect(() => {
    if (!cat) return;
    writeUrl({
      routes: [...picked],
      stop: stop === null ? null : cat.stops[stop]!.id,
      route: route === null ? null : cat.routes[route]!.id,
      tab,
    });
  }, [cat, picked, stop, route, tab]);

  const index = useIndex(cat?.routes);

  const chosen = usePositions(index, picked);

  const showStop = (i: number) => {
    const s = cat?.stops[i];
    if (!s) return;
    openTab("map");
    setStop(i);
    setPlace(null);
    setFocus({ lat: s.lat, lon: s.lon });
  };

  /** The map shows only this line */
  const lineOpen = tab === "lines" && route !== null;
  // The planner's option while one is shown, so another way can be weighed
  // against the one followed
  const planned = lineOpen || tab !== "plan" ? null : journey;
  const drawn = lineOpen ? null : (planned ?? following);

  const { geo, indexes, lines, fit, stops, faint } = useMapLayers({
    cat,
    route: lineOpen ? route : null,
    drawn,
    framed: planned,
    chosen,
    allLines,
    onError: failed,
  });

  useEffect(() => {
    if (cat) live.setRoutes(indexes);
  }, [live, cat, indexes]);

  const ways = useMemo(
    () => (route === null ? [] : directions(geo?.routes[route])),
    [geo, route],
  );

  /** A journey followed adds the stops its rides board and leave at, for
   * when its vehicles get there; the line open adds its stops, last, so they
   * are the ones the socket's cap drops */
  const watched = useMemo(() => {
    const out = new Set(pins);
    if (stop !== null) out.add(stop);
    for (const leg of following?.legs ?? []) {
      if (leg.kind === "ride") out.add(leg.a).add(leg.b);
    }
    for (const s of lineOpen ? (ways[way]?.stops ?? []) : []) out.add(s);
    return [...out].slice(0, MAX_WATCHED);
  }, [pins, stop, following, lineOpen, ways, way]);

  useEffect(() => {
    if (cat) live.setStops(watched);
  }, [live, cat, watched]);

  // Here rather than in its card, which a change of tab unmounts
  const { progress, caught, here } = useFollow(
    following,
    live,
    cat ?? undefined,
    // where a journey followed before the page loaded had got to
    followed?.stage,
  );
  // The walk under way is drawn from where I am, not from where it was planned
  const onMap = useMemo(
    () =>
      drawn !== null && drawn === following && here && progress !== null && progress !== "denied"
        ? walkingFrom(drawn, progress, here)
        : drawn,
    [drawn, following, here, progress],
  );

  const follow = (next: Followed | null) => {
    holdFollowed(next);
    setFollowed(next);
  };

  /** Plans the rest of the way: from on board the vehicle ridden, else from
   *  where you are, which is asked for only now */
  const searchAgain = () => {
    if (!followed || progress === null || progress === "denied") return;
    const { stage } = progress;
    planner.setTo(followed.to);
    if (stage.kind === "ride" && stage.veh !== null) {
      planner.board({ veh: stage.veh, route: followed.journey.legs[stage.leg]!.route ?? null });
    } else {
      planner.setFrom(null);
      planner.hereFor("from");
    }
    planner.setAsk(true);
    openTab("plan");
  };

  const setPinned = (next: number[]) => {
    if (!cat) return;
    session.savePins(next.map((i) => cat.stops[i]!.id));
  };

  // A place saved under a name in use replaces that one, so it is asked first
  // where the name was not typed into a field that says so
  const savePlace = (name: string, lat: number, lon: number) => {
    if (replaces(places, name, { lat, lon })) setReplacing({ name, lat, lon });
    else keepPlaces(saved(places, name, lat, lon));
  };

  const showPlace = (at: Shown) => {
    openTab("map");
    setStop(null);
    setVeh(null);
    setPlace(at);
    setFocus({ lat: at.lat, lon: at.lon });
  };

  /** The planner, to the place shown and from wherever it already starts - or
   *  from where you are, which is asked for only now */
  const planTo = (at: Shown) => {
    planner.setTo({ lat: at.lat, lon: at.lon, name: at.name });
    if (planner.from === null) planner.hereFor("from");
    planner.setAsk(true);
    setPlace(null);
    openTab("plan");
  };

  /** The planner, from or to a point held on the map; to it, from where you
   *  are unless it already starts somewhere */
  const planAt = (which: "from" | "to", at: Held) => {
    setHeld(null);
    planner.setEnd(which, { lat: at.lat, lon: at.lon });
    if (which === "to" && planner.from === null) planner.hereFor("from");
    planner.setAsk(true);
    setPlace(null);
    openTab("plan");
  };

  const openRoute = (i: number) => {
    if (!cat) return;
    if (i !== route) {
      setWay(0);
      setLineFolded(false);
    }
    setRoute(i);
    const next = openedLately(recent, cat.routes[i]!.id);
    setRecent(next);
    saveRecent(next);
    openTab("lines");
  };

  const { load } = session;

  if (code !== null && !me)
    return <SignIn code={code} onIn={() => void load()} />;
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
      <Splash
        text={notice}
        onRetry={() => {
          setNotice(null);
          void loadCatalog(me);
        }}
      />
    );

  // Top 19 and bottom 20: a panel grows with what it holds down to the tab bar,
  // rather than standing full height around one line
  const tall = "max-h-[calc(100%-9.75rem)]";
  // On a phone the other tabs' panels span the width, so the map's corner
  // controls would only show blurred through them
  const mapOnly = tab === "map" ? "" : "max-sm:hidden";

  return (
    // Everything floats over the map, so `pointer-events-none` on the strips
    // that only position things keeps the gaps between them draggable map
    <div className="relative h-dvh overflow-hidden bg-plate text-slate-100">
      {/* Mounted whatever the tab is: remounting the map re-downloads the style */}
      <MapCanvas
        catalog={cat}
        live={live}
        lowFloor={lowFloor}
        // Only while its card is open: closing it, or picking another, lets go
        tracked={tracked !== null && tracked === veh ? tracked : null}
        onUntrack={() => setTracked(null)}
        stops={stops}
        faint={faint}
        selected={stop}
        onPickStop={(i) => {
          setStop(i);
          setPlace(null);
          if (i !== null) setVeh(null);
        }}
        vehicle={veh}
        onPickVehicle={(i) => {
          setVeh(i);
          setPlace(null);
        }}
        focus={focus}
        fit={fit}
        panel={panel}
        picking={planner.picking !== null}
        onPickPoint={planner.pickAt}
        onHoldPoint={setHeld}
        marks={
          place && tab === "map"
            ? [...planner.marks, { lat: place.lat, lon: place.lon, label: PLACE_MARK }]
            : planner.marks
        }
        journey={onMap}
        locate={following !== null}
        pinned={pins}
        places={places}
        shapes={geo}
        lines={lines}
        directed={lineOpen ? route : null}
        traffic={traffic}
        theme={theme}
        covered={tab !== "map" && !lineOpen}
      />
      {held && (
        <HoldMenu
          at={held}
          label={pointLabel(cat, held)}
          isTaken={(name) => replaces(places, name, held)}
          onSave={(name) => {
            keepPlaces(saved(places, name, held.lat, held.lon));
            setHeld(null);
          }}
          onTo={() => planAt("to", held)}
          onFrom={() => planAt("from", held)}
          onNear={() => {
            setAround({ lat: held.lat, lon: held.lon });
            setHeld(null);
          }}
          onClose={() => setHeld(null)}
        />
      )}
      {replacing && (
        <Confirm
          text={t.placeTaken}
          action={t.replace}
          onConfirm={() => {
            keepPlaces(saved(places, replacing.name, replacing.lat, replacing.lon));
            setReplacing(null);
          }}
          onCancel={() => setReplacing(null)}
        />
      )}

      <header className="pointer-events-none absolute inset-x-0 top-0 z-30 flex items-start gap-2 p-3">
        <div className="pointer-events-auto min-w-0 flex-1 sm:max-w-sm">
          <StopSearch
            catalog={cat}
            onGo={showStop}
            onPlace={showPlace}
            onSave={savePlace}
            places={places}
            around={around}
          />
        </div>
        <span
          className="bar pointer-events-auto ml-auto flex h-10 items-center gap-2 px-3.5 text-xs text-slate-400"
          title={`${t.connection[connection]} - ${t.vehicles(count)}`}
        >
          <span
            className={`size-2 rounded-full ${
              connection === "live" ? "bg-emerald-500" : "bg-amber-500"
            }`}
          />
          {/* On a phone the search field needs the room more than the word does */}
          <span className="sm:hidden">{count}</span>
          <span className="max-sm:hidden">{t.vehicles(count)}</span>
        </span>
      </header>

      <div className={`absolute right-3 top-31 z-20 ${mapOnly}`}>
        <Menu
          icon="layers"
          label={t.layers}
          open={layersOpen}
          lit={allLines || jams}
          onToggle={setLayersOpen}
        >
          <LayersPanel
            lines={allLines}
            onLines={(on) => {
              setAllLines(on);
              saveFlag(LINES_KEY, on);
            }}
            traffic={jams}
            onTraffic={(on) => {
              setJams(on);
              saveFlag(TRAFFIC_KEY, on);
            }}
            theme={theme}
            onTheme={(next) => {
              setTheme(next);
              saveTheme(next);
            }}
            lowFloor={lowFloor}
            onLowFloor={(on) => {
              setLowFloor(on);
              saveFlag(LOW_FLOOR_KEY, on);
            }}
            blur={!noBlur}
            onBlur={(on) => {
              setNoBlur(!on);
              saveFlag(NO_BLUR_KEY, !on);
            }}
          />
        </Menu>
      </div>

      {jams && (
        <div className={`panel absolute right-3 top-43 z-10 w-44 p-2.5 text-xs text-slate-400 ${mapOnly}`}>
          <div className="flex h-1.5 overflow-hidden rounded-full">
            {RAMP.map(([, colour]) => (
              <span
                key={colour}
                className="flex-1"
                style={{ background: colour }}
              />
            ))}
          </div>
          <p className="mt-1.5 flex justify-between">
            <span>{t.trafficFree}</span>
            <span>{t.trafficSlow}</span>
          </p>
          <p className="mt-1.5 text-slate-500">{t.trafficHint}</p>
        </div>
      )}

      <div className="pointer-events-none absolute inset-x-3 top-19 z-40 flex flex-col items-center gap-2 max-sm:right-16">
        {notice !== null ? (
          <Banner tone="error" text={notice} onClose={() => setNotice(null)} />
        ) : (
          info !== null && <Banner tone="info" text={info} onClose={() => setInfo(null)} />
        )}
        {quiet && !quietShut && (
          <Banner
            tone="warn"
            icon="siren"
            text={t.quietTitle}
            detail={t.quietDetail}
            onClose={() => setQuietShut(true)}
          />
        )}
      </div>

      {tab === "plan" && (
        <aside
          ref={panel}
          className={`panel absolute right-3 top-19 z-20 w-96 max-w-[calc(100vw-1.5rem)] overflow-y-auto p-3 ${tall}`}
        >
          <JourneyPanel
            catalog={cat}
            from={planner.from}
            to={planner.to}
            picking={planner.picking}
            onPick={planner.setPicking}
            onSwap={planner.swap}
            onHere={planner.hereFor}
            onShow={setJourney}
            onFollow={(j) => {
              follow({ journey: j, to: planner.to!, tag: catalogTag() ?? "" });
              openTab("map");
            }}
            ask={planner.ask}
            onAsked={() => planner.setAsk(false)}
            folded={folded}
            onFold={setFolded}
            onLine={openRoute}
            places={places}
            onSavePlace={savePlace}
            onPoint={planner.setEnd}
            onStop={showStop}
          />
        </aside>
      )}

      {tab === "mine" && (
        <section
          className={`panel absolute left-3 right-3 top-19 z-20 mx-auto max-w-lg overflow-y-auto p-4 ${tall}`}
        >
          <MinePanel
            catalog={cat}
            arrivals={live.arrivals}
            watching={picked}
            onToggle={session.togglePicked}
            pins={pins}
            onPins={setPinned}
            onStop={showStop}
            onRoute={openRoute}
            places={places}
            onPlaces={keepPlaces}
            onPlace={showPlace}
            sets={session.routeSets.sets}
            active={session.routeSets.active}
            onActivate={session.routeSets.activate}
            onDelete={session.routeSets.remove}
            username={me.username}
            section={mineSection}
            onSection={setMineSection}
            account={
              <AccountSettings
                passwordChange={me.password_change ?? false}
                onOut={session.signOut}
              />
            }
          />
        </section>
      )}

      {tab === "lines" && (
        <aside
          ref={panel}
          // A folded line is its title alone, so the map shows the line
          className={`panel absolute left-3 top-19 z-20 w-80 max-w-[calc(100vw-1.5rem)] p-3 ${route !== null && lineFolded ? "" : "bottom-20"}`}
        >
          {route === null ? (
            <LinesBrowse
              catalog={cat}
              picked={picked}
              onToggle={session.togglePicked}
              onClear={session.clearPicked}
              onPickAll={() => session.routeSets.pickAll(cat.routes.map((r) => r.id))}
              onOpen={openRoute}
              recent={recent}
              sets={session.routeSets.sets}
              active={session.routeSets.active}
              onActivate={session.routeSets.activate}
              onCreate={session.routeSets.create}
              onUpdate={session.routeSets.update}
            />
          ) : (
            <LineView
              catalog={cat}
              route={route}
              ways={ways}
              way={way}
              onWay={setWay}
              arrivals={live.arrivals}
              watching={picked.has(cat.routes[route]!.id)}
              onWatch={() => session.togglePicked(cat.routes[route]!.id)}
              onStop={showStop}
              onBack={() => setRoute(null)}
              folded={lineFolded}
              onFold={setLineFolded}
            />
          )}
        </aside>
      )}

      {tab === "map" && (stop !== null || veh !== null || place || following) && (
        <div
          className={`pointer-events-none absolute left-3 bottom-20 right-3 z-10 mx-auto flex max-w-md flex-col gap-2`}
        >
          {stop !== null ? (
            <StopCard
              lowFloor={lowFloor}
              catalog={cat}
              stop={stop}
              arrivals={live.arrivals[String(stop)]}
              pinned={pins.includes(stop)}
              onPin={() =>
                setPinned(
                  pins.includes(stop)
                    ? pins.filter((i) => i !== stop)
                    : [...pins, stop],
                )
              }
              watching={picked}
              onToggle={session.togglePicked}
              onRoute={openRoute}
              onClose={() => setStop(null)}
            />
          ) : veh === null ? (
            place && (
              <PlaceCard
                place={place}
                isSaved={places.some((p) => samePlace(place, p))}
                onSave={() => savePlace(place.name, place.lat, place.lon)}
                onGo={() => planTo(place)}
                onClose={() => setPlace(null)}
              />
            )
          ) : (
            <VehicleCard
              // Another vehicle is another card, not this one's calls kept
              key={veh}
              lowFloor={lowFloor}
              following={tracked === veh}
              onFollow={(on) => setTracked(on ? veh : null)}
              catalog={cat}
              veh={veh}
              onStop={(i) => {
                setStop(i);
                setVeh(null);
              }}
              watching={picked}
              onToggle={session.togglePicked}
              onRoute={openRoute}
              onAboard={(on) => {
                planner.board(on);
                setVeh(null);
                openTab("plan");
              }}
              onClose={() => setVeh(null)}
            />
          )}
          {following && (
            <FollowCard
              catalog={cat}
              journey={following}
              live={live}
              progress={progress}
              caught={caught}
              onSearch={searchAgain}
              onEnd={() => follow(null)}
            />
          )}
        </div>
      )}

      {/* One font weight throughout, so choosing a tab does not resize its
          label and slide the others. Equal columns where they fit; a phone
          has room only for each label's own width */}
      {/* The bar's inset is each tab's own padding, so a tap anywhere on the
          bar lands on a tab */}
      <nav className="bar absolute bottom-3 left-1/2 z-30 grid w-max -translate-x-1/2 grid-flow-col text-sm sm:grid-cols-4">
        {TABS.map((v) => (
          <button
            key={v}
            onClick={() => {
              openTab(v);
              setLayersOpen(false);
            }}
            className="group rounded-full p-1 font-medium"
          >
            <span
              className={`block rounded-full px-2 py-1.5 transition-colors sm:px-4 ${
                tab === v
                  ? "bg-accent/15 text-accent"
                  : "text-slate-400 group-hover:text-slate-200"
              }`}
            >
              {TAB_NAMES[v]}
            </span>
          </button>
        ))}
      </nav>

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
