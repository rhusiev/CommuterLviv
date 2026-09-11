import { useEffect, useMemo, useRef, useState } from "react";
import { metres } from "../lib/geo";
import type { Catalog } from "../lib/types";
import { t } from "../lib/i18n";

const LIMIT = 8;

/** Metres: past this "near me" is an IP geolocation, not a nearby stop */
const NEAR = 2000;

type Props = {
  catalog: Catalog;
  onGo: (stop: number) => void;
};

export function StopSearch({ catalog, onGo }: Props) {
  const [query, setQuery] = useState("");
  const [cursor, setCursor] = useState(0);
  const [near, setNear] = useState<{ stop: number; away: number }[] | null>(null);
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
        const found = catalog.stops
          .map((s, stop) => ({ stop, away: metres(me, s) }))
          .filter((h) => h.away <= NEAR)
          .sort((a, b) => a.away - b.away)
          .slice(0, LIMIT);
        setNear(found);
        if (found.length === 0) setWhy(t.nothingNear);
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

  const shown = near === null ? hits : near.map((h) => h.stop);

  const go = (i: number | undefined) => {
    if (i === undefined) return;
    onGo(i);
    setQuery("");
    setNear(null);
    setWhy("");
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
          if (e.key === "ArrowDown") setCursor((c) => Math.min(c + 1, shown.length - 1));
          else if (e.key === "ArrowUp") setCursor((c) => Math.max(c - 1, 0));
          else if (e.key === "Enter") go(shown[cursor]);
          else if (e.key === "Escape") {
            setQuery("");
            setNear(null);
          } else return;
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
      {why !== "" && (
        <p className="panel absolute inset-x-0 top-full z-30 mt-2 px-3 py-2 text-xs text-slate-400">
          {why}
        </p>
      )}
      {shown.length > 0 && (
        <ul className="panel absolute inset-x-0 top-full z-30 mt-2 overflow-hidden p-1">
          {shown.map((i, n) => {
            const s = catalog.stops[i]!;
            return (
              <li key={s.id}>
                <button
                  onClick={() => go(i)}
                  onMouseEnter={() => setCursor(n)}
                  data-hit={s.name}
                  className={`block w-full rounded-control px-2.5 py-1.5 text-left text-sm ${
                    n === cursor ? "bg-accent/15 text-accent" : "text-slate-300"
                  }`}
                >
                  <span className="truncate">{s.name}</span>
                  <span className="ml-2 text-xs text-slate-500">
                    {near === null
                      ? s.routes
                          .map((r) => catalog.routes[r]?.short)
                          .filter(Boolean)
                          .slice(0, 6)
                          .join(" ")
                      : t.away(Math.round(near[n]!.away))}
                  </span>
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
