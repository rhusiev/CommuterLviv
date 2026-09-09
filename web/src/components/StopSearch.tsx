import { useEffect, useMemo, useRef, useState } from "react";
import { metres } from "../lib/geo";
import type { Catalog } from "../lib/types";

/** Find a stop by name, or by standing next to it. The catalog is a thousand
 * stops with repeated names - every direction of a street is its own stop - so
 * a hit shows which routes call there, which is the only thing that tells two
 * of them apart. Standing next to one is the other way to tell: the nearby list
 * carries the distance instead of the routes. */

const LIMIT = 8;

/** Past this, "near me" is not answering the question that was asked. The
 * city's stops are rarely 2 km apart; a browser that says Kyiv because it is
 * geolocating an IP address should say so rather than list a stop. */
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
    // A name that starts with the query is what was meant far more often than
    // one that merely contains it, so those come first and the scan stops
    // early rather than sorting a thousand stops on every keystroke
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

  /** The browser asks the person, every time, and can take a while about it.
   * Nothing is stored and no position is ever sent anywhere: the catalog is
   * already here, so the whole answer is computed in the tab. */
  const locate = () => {
    setQuery("");
    setWhy("");
    if (!navigator.geolocation) {
      setWhy("this browser will not say where it is");
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
        if (found.length === 0) setWhy("no stop within 2 km of where you are");
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
        placeholder="Find a stop"
        className="w-32 rounded-md border border-slate-800 bg-slate-900 px-2 py-1 pr-7 text-sm text-slate-100 outline-none focus:w-56 focus:border-sky-600"
      />
      <button
        onClick={locate}
        disabled={locating}
        title="Stops near me"
        className="absolute right-1 top-1/2 -translate-y-1/2 rounded px-1 text-sm text-slate-500 hover:text-sky-300 disabled:text-slate-700"
      >
        ◎
      </button>
      {why !== "" && (
        <p className="absolute left-0 top-full z-30 mt-1 w-72 rounded-md border border-slate-800 bg-slate-950/95 px-2 py-1.5 text-xs text-slate-400 backdrop-blur">
          {why}
        </p>
      )}
      {shown.length > 0 && (
        <ul className="absolute left-0 top-full z-30 mt-1 w-72 overflow-hidden rounded-md border border-slate-800 bg-slate-950/95 backdrop-blur">
          {shown.map((i, n) => {
            const s = catalog.stops[i]!;
            return (
              <li key={s.id}>
                <button
                  onClick={() => go(i)}
                  onMouseEnter={() => setCursor(n)}
                  data-hit={s.name}
                  className={`block w-full px-2 py-1.5 text-left text-sm ${
                    n === cursor ? "bg-slate-800 text-slate-100" : "text-slate-300"
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
                      : `${Math.round(near[n]!.away)} m`}
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
