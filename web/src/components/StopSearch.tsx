import { useEffect, useMemo, useRef, useState } from "react";
import { api } from "../lib/api";
import { metres } from "../lib/geo";
import type { Catalog, Found } from "../lib/types";
import { t } from "../lib/i18n";

const LIMIT = 8;

/** Metres: past this "near me" is an IP geolocation, not a nearby stop */
const NEAR = 2000;

/** A keystroke within this cancels the request the one before it started */
const SETTLE = 250;

/** Stops are the catalog in memory and answer instantly; places are a request,
 * so they arrive under the stops rather than reordering what is already there. */
type Row = { stop: number; away?: number } | { place: Found };

const isStop = (r: Row): r is { stop: number; away?: number } => "stop" in r;

type Props = {
  catalog: Catalog;
  onGo: (stop: number) => void;
  onPlace: (place: Found) => void;
  onSave: (name: string, lat: number, lon: number) => void;
};

export function StopSearch({ catalog, onGo, onPlace, onSave }: Props) {
  const [query, setQuery] = useState("");
  const [cursor, setCursor] = useState(0);
  const [near, setNear] = useState<{ stop: number; away: number }[] | null>(null);
  const [found, setFound] = useState<Found[]>([]);
  const [locating, setLocating] = useState(false);
  const [why, setWhy] = useState("");
  const box = useRef<HTMLDivElement>(null);

  const hits = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (q.length < 2) return [];
    const out: number[] = [];
    // Prefix hits first, and the scan stops early rather than sorting a
    // thousand stops on every keystroke
    const rest: number[] = [];
    for (let i = 0; i < catalog.stops.length; i++) {
      const name = catalog.stops[i]!.name.toLowerCase();
      const at = name.indexOf(q);
      if (at === 0) out.push(i);
      else if (at > 0 && rest.length < LIMIT) rest.push(i);
      if (out.length >= LIMIT) break;
    }
    return [...out, ...rest].slice(0, LIMIT);
  }, [catalog, query]);

  useEffect(() => {
    const q = query.trim();
    if (near !== null || q.length < 2) {
      setFound([]);
      return;
    }
    const stop = new AbortController();
    const timer = window.setTimeout(() => {
      api.search(q, stop.signal).then(
        (got) => {
          setFound(got.places.slice(0, LIMIT));
          setWhy("");
        },
        () => {
          if (stop.signal.aborted) return;
          setFound([]);
          setWhy(t.noPlaceSearch);
        },
      );
    }, SETTLE);
    return () => {
      clearTimeout(timer);
      stop.abort();
    };
  }, [query, near]);

  useEffect(() => setCursor(0), [query, near]);

  const locate = () => {
    setQuery("");
    setWhy("");
    if (!navigator.geolocation) {
      setWhy(t.noGeolocation);
      return;
    }
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setLocating(false);
        const me = { lat: pos.coords.latitude, lon: pos.coords.longitude };
        const close = catalog.stops
          .map((s, stop) => ({ stop, away: metres(me, s) }))
          .filter((h) => h.away <= NEAR)
          .sort((a, b) => a.away - b.away)
          .slice(0, LIMIT);
        setNear(close);
        if (close.length === 0) setWhy(t.nothingNear);
      },
      (err) => {
        setLocating(false);
        setWhy(err.code === err.PERMISSION_DENIED ? "location refused" : "no location fix");
      },
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 60000 },
    );
  };

  useEffect(() => {
    const away = (e: PointerEvent) => {
      if (box.current?.contains(e.target as Node)) return;
      setQuery("");
      setNear(null);
      setWhy("");
    };
    document.addEventListener("pointerdown", away);
    return () => document.removeEventListener("pointerdown", away);
  }, []);

  const rows: Row[] =
    near === null
      ? [...hits.map((stop) => ({ stop })), ...found.map((place) => ({ place }))]
      : near.map((h) => ({ stop: h.stop, away: h.away }));

  const clear = () => {
    setQuery("");
    setNear(null);
    setFound([]);
    setWhy("");
  };

  const go = (row: Row | undefined) => {
    if (!row) return;
    if (isStop(row)) onGo(row.stop);
    else onPlace(row.place);
    clear();
  };

  return (
    <div ref={box} className="relative">
      <input
        value={query}
        onChange={(e) => {
          setQuery(e.target.value);
          setNear(null);
          setWhy("");
        }}
        onKeyDown={(e) => {
          if (e.key === "ArrowDown") setCursor((c) => Math.min(c + 1, rows.length - 1));
          else if (e.key === "ArrowUp") setCursor((c) => Math.max(c - 1, 0));
          else if (e.key === "Enter") go(rows[cursor]);
          else if (e.key === "Escape") clear();
          else return;
          e.preventDefault();
        }}
        placeholder={t.findStop}
        className="field-bar py-2.5 pr-8"
      />
      <button
        onClick={locate}
        disabled={locating}
        title={t.nearMe}
        className="absolute right-2 top-1/2 -translate-y-1/2 rounded-full px-1 text-sm text-slate-500 hover:text-accent disabled:text-slate-600"
      >
        ◎
      </button>
      {why !== "" && rows.length === 0 && (
        <p className="panel absolute inset-x-0 top-full z-30 mt-2 px-3 py-2 text-xs text-slate-400">
          {why}
        </p>
      )}
      {rows.length > 0 && (
        <ul className="panel absolute inset-x-0 top-full z-30 mt-2 overflow-hidden p-1">
          {rows.map((row, n) => {
            // Named only once the list holds both kinds of thing
            const heading =
              found.length === 0 || near !== null
                ? null
                : n === 0 && hits.length > 0
                  ? t.stopHits
                  : n === hits.length
                    ? t.placeHits
                    : null;
            const it = isStop(row)
              ? {
                  ...catalog.stops[row.stop]!,
                  where:
                    row.away === undefined
                      ? catalog.stops[row.stop]!.routes
                          .map((r) => catalog.routes[r]?.short)
                          .filter(Boolean)
                          .slice(0, 6)
                          .join(" ")
                      : t.away(Math.round(row.away)),
                }
              : row.place;
            return (
              <li key={n}>
                {heading !== null && (
                  <p className="px-2.5 pb-0.5 pt-1.5 text-xs uppercase tracking-wide text-slate-500">
                    {heading}
                  </p>
                )}
                <div
                  onMouseEnter={() => setCursor(n)}
                  className={`flex items-center rounded-control ${
                    n === cursor ? "bg-accent/15" : ""
                  }`}
                >
                  <button
                    onClick={() => go(row)}
                    data-hit={it.name}
                    className={`min-w-0 flex-1 px-2.5 py-1.5 text-left text-sm ${
                      n === cursor ? "text-accent" : "text-slate-300"
                    }`}
                  >
                    <span className="truncate">{it.name}</span>
                    <span className="ml-2 text-xs text-slate-500">{it.where}</span>
                  </button>
                  <button
                    onClick={() => onSave(it.name, it.lat, it.lon)}
                    title={t.savePlace}
                    className="shrink-0 px-2 py-1.5 text-sm text-slate-500 hover:text-accent"
                  >
                    ☆
                  </button>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
