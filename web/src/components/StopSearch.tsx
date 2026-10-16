import { type ReactNode, useEffect, useMemo, useRef, useState } from "react";
import { api } from "../lib/api";
import { metres } from "../lib/geo";
import { MIN_TYPED, score, words } from "../lib/match";
import { matching } from "../lib/places";
import { hereOnce, type NoFix } from "../lib/position";
import type { Catalog, Found, Place } from "../lib/types";
import { t } from "../lib/i18n";

const LIMIT = 8;

/** Metres: past this "near me" is an IP geolocation, not a nearby stop */
const NEAR = 2000;

/** A keystroke within this cancels the request the one before it started */
const SETTLE = 250;

/** Saved places and stops are in memory and answer instantly; places are a
 * request, so they arrive under the stops rather than reordering what is
 * already there. */
type Row = { saved: Place } | { stop: number; away?: number } | { place: Found };

type Section = { title: string; rows: Row[] };

type Props = {
  catalog: Catalog;
  onGo: (stop: number) => void;
  onPlace: (place: Place) => void;
  places: Place[];
  onSave: (name: string, lat: number, lon: number) => void;
  /** Set when the search stands in for a field: it opens focused, offers
   *  `idle` until something is typed, and asks to be dismissed when done */
  inline?: { placeholder: string; idle: ReactNode; onDismiss: () => void };
};

export function StopSearch({ catalog, onGo, onPlace, onSave, places, inline }: Props) {
  const [query, setQuery] = useState("");
  const [cursor, setCursor] = useState(0);
  const [near, setNear] = useState<{ stop: number; away: number }[] | null>(null);
  const [found, setFound] = useState<Found[]>([]);
  const [locating, setLocating] = useState(false);
  const [why, setWhy] = useState("");
  const box = useRef<HTMLDivElement>(null);

  const names = useMemo(() => catalog.stops.map((s) => words(s.name)), [catalog]);
  const hits = useMemo(() => {
    const q = words(query);
    if (q.join("").length < MIN_TYPED) return [];
    const scored: [number, number][] = [];
    names.forEach((name, i) => {
      const s = score(q, name);
      if (s > 0) scored.push([s, i]);
    });
    // Shorter names first among equals: "Ринок" before "Ринок Шувар"
    scored.sort(([a, i], [b, j]) => b - a || catalog.stops[i]!.name.length - catalog.stops[j]!.name.length);
    return scored.slice(0, LIMIT).map(([, i]) => i);
  }, [catalog, names, query]);
  const mine = useMemo(() => matching(places, query).slice(0, LIMIT), [places, query]);

  useEffect(() => {
    const q = query.trim();
    if (near !== null || q.length < MIN_TYPED) {
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
    hereOnce({ enableHighAccuracy: true, timeout: 10000, maximumAge: 60000 }).then(
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
      (why: NoFix) => {
        setLocating(false);
        setWhy(t.noFix[why]);
      },
    );
  };

  const dismiss = useRef(inline?.onDismiss);
  dismiss.current = inline?.onDismiss;

  useEffect(() => {
    const away = (e: PointerEvent) => {
      if (box.current?.contains(e.target as Node)) return;
      setQuery("");
      setNear(null);
      setWhy("");
      dismiss.current?.();
    };
    document.addEventListener("pointerdown", away);
    return () => document.removeEventListener("pointerdown", away);
  }, []);

  const sections: Section[] = (
    near === null
      ? [
          { title: t.places, rows: mine.map((saved) => ({ saved })) },
          { title: t.stopHits, rows: hits.map((stop) => ({ stop })) },
          { title: t.placeHits, rows: found.map((place) => ({ place })) },
        ]
      : [{ title: t.stopHits, rows: near.map((h) => ({ stop: h.stop, away: h.away })) }]
  ).filter((s) => s.rows.length > 0);
  const rows = sections.flatMap((s) => s.rows);
  // Named only once the list holds more than one kind of thing
  const headings = new Map<number, string>();
  if (sections.length > 1) {
    let at = 0;
    for (const s of sections) {
      headings.set(at, s.title);
      at += s.rows.length;
    }
  }

  const clear = () => {
    setQuery("");
    setNear(null);
    setFound([]);
    setWhy("");
    inline?.onDismiss();
  };

  const go = (row: Row | undefined) => {
    if (!row) return;
    if ("stop" in row) onGo(row.stop);
    else onPlace("saved" in row ? row.saved : row.place);
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
        placeholder={inline?.placeholder ?? t.findStop}
        autoFocus={inline !== undefined}
        className={inline ? "field w-full py-1.5" : "field-bar py-2.5 pr-8"}
      />
      {!inline && (
        <button
          onClick={locate}
          disabled={locating}
          title={t.nearMe}
          className="absolute right-2 top-1/2 -translate-y-1/2 rounded-full px-1 text-sm text-slate-500 hover:text-accent disabled:text-slate-600"
        >
          ◎
        </button>
      )}
      {inline && query.trim() === "" && (
        <div className="panel absolute inset-x-0 top-full z-30 mt-1 p-1 text-sm">{inline.idle}</div>
      )}
      {why !== "" && rows.length === 0 && (
        <p className="panel absolute inset-x-0 top-full z-30 mt-2 px-3 py-2 text-xs text-slate-400">
          {why}
        </p>
      )}
      {rows.length > 0 && (
        <ul className="panel absolute inset-x-0 top-full z-30 mt-2 overflow-hidden p-1">
          {rows.map((row, n) => {
            const heading = headings.get(n);
            const it = "saved" in row
              ? { ...row.saved, where: "" }
              : "stop" in row
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
                {heading !== undefined && (
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
                  {"saved" in row ? (
                    <span className="shrink-0 px-2 py-1.5 text-sm text-accent">★</span>
                  ) : (
                    <button
                      onClick={() => onSave(it.name, it.lat, it.lon)}
                      title={t.savePlace}
                      className="shrink-0 px-2 py-1.5 text-sm text-slate-500 hover:text-accent"
                    >
                      ☆
                    </button>
                  )}
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
