import type { Route } from "./types";

/** One pre-rendered badge per route, drawn once and blitted thereafter.
 *
 * The alternative is `fillText` four hundred times per animation frame, which
 * is where a canvas map actually spends its budget: laying out text is orders
 * of magnitude dearer than copying a bitmap. Sprites are rebuilt only when the
 * device pixel ratio changes. */

export const R = 13; // badge radius in CSS pixels

export function hue(short: string): number {
  let h = 0;
  for (let i = 0; i < short.length; i++) h = (h * 31 + short.charCodeAt(i)) % 360;
  return h;
}

export function colour(short: string, type: string): string {
  // Trolleybuses and trams read as cooler, buses warmer, but each route still
  // gets its own hue so two neighbours are never the same circle
  const base = type === "tram" ? 200 : type === "trolleybus" ? 260 : 20;
  return `hsl(${(base + (hue(short) % 90)) % 360} 70% 52%)`;
}

/** The number without the letter the city puts in front of it: `А25` is a bus,
 * `Т07` a tram, `Тр33` a trolleybus. The kind is drawn as a glyph and as a hue
 * instead, so the badge is left saying the one thing a rider says out loud -
 * and three characters fit a circle that four did not. */
export function number(short: string): string {
  return short.replace(/^(Тр|Т|А)/, "").replace(/^0+(?=.)/, "");
}

export type Sprites = { badges: HTMLCanvasElement[]; dpr: number };

export function build(routes: Route[], dpr: number): Sprites {
  return { badges: routes.map((r) => badge(r, dpr)), dpr };
}

function badge(route: Route, dpr: number): HTMLCanvasElement {
  const size = Math.ceil(R * 2 * dpr);
  const c = document.createElement("canvas");
  c.width = c.height = size;
  const g = c.getContext("2d")!;
  g.scale(dpr, dpr);

  g.beginPath();
  g.arc(R, R, R - 1.5, 0, Math.PI * 2);
  g.fillStyle = colour(route.short, route.type);
  g.fill();
  g.lineWidth = 1.5;
  g.strokeStyle = "rgba(8,10,14,0.85)";
  g.stroke();

  const label = number(route.short).slice(0, 4);
  g.font = `600 ${label.length > 3 ? 9 : label.length > 2 ? 11 : 13}px ui-sans-serif, system-ui, sans-serif`;
  g.textAlign = "center";
  g.textBaseline = "middle";
  g.fillStyle = "#0b0f14";
  g.fillText(label, R, R + 0.5);
  return c;
}
