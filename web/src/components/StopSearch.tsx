import { useEffect, useMemo, useRef, useState } from "react";
import type { Catalog } from "../lib/types";

/** Find a stop by name. The catalog is a thousand stops with repeated names -
 * every direction of a street is its own stop - so a hit shows which routes
 * call there, which is the only thing that tells two of them apart. */

const LIMIT = 8;

type Props = {
  catalog: Catalog;
  onGo: (stop: number) => void;
};

export function StopSearch({ catalog, onGo }: Props) {
  const [query, setQuery] = useState("");
  const [cursor, setCursor] = useState(0);
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

  useEffect(() => setCursor(0), [query]);

  useEffect(() => {
    const away = (e: PointerEvent) => {
      if (!box.current?.contains(e.target as Node)) setQuery("");
    };
    document.addEventListener("pointerdown", away);
    return () => document.removeEventListener("pointerdown", away);
  }, []);

  const go = (i: number | undefined) => {
    if (i === undefined) return;
    onGo(i);
    setQuery("");
  };

  return (
    <div ref={box} className="relative">
      <input
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "ArrowDown") setCursor((c) => Math.min(c + 1, hits.length - 1));
          else if (e.key === "ArrowUp") setCursor((c) => Math.max(c - 1, 0));
          else if (e.key === "Enter") go(hits[cursor]);
          else if (e.key === "Escape") setQuery("");
          else return;
          e.preventDefault();
        }}
        placeholder="Find a stop"
        className="w-32 rounded-md border border-slate-800 bg-slate-900 px-2 py-1 text-sm text-slate-100 outline-none focus:w-56 focus:border-sky-600"
      />
      {hits.length > 0 && (
        <ul className="absolute left-0 top-full z-30 mt-1 w-72 overflow-hidden rounded-md border border-slate-800 bg-slate-950/95 backdrop-blur">
          {hits.map((i, n) => {
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
                    {s.routes
                      .map((r) => catalog.routes[r]?.short)
                      .filter(Boolean)
                      .slice(0, 6)
                      .join(" ")}
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
