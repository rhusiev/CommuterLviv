/** The basemap's look. VersaTiles serves five styles of OpenStreetMap at one
 * URL shape, over the same tiles, so switching is a `setStyle` and no reload.
 *
 * `dark` is not decoration: the vehicles and stops are drawn on a canvas above
 * the map, and a near-white marker that reads perfectly on `shadow` disappears
 * on `neutrino`. Every overlay colour is picked from here. */

export type Theme = {
  id: string;
  name: string;
  dark: boolean;
};

/** Measured from each style's own `background-color` on 2026-09-07 */
export const THEMES: Theme[] = [
  { id: "shadow", name: "Shadow", dark: true },
  { id: "eclipse", name: "Eclipse", dark: true },
  { id: "graybeard", name: "Graybeard", dark: false },
  { id: "neutrino", name: "Neutrino", dark: false },
  { id: "colorful", name: "Colorful", dark: false },
];

const KEY = "commuterlviv.theme";

/** Where the basemap comes from. The public server unless this deployment
 * serves its own, which `/api/health` says and `setSelfTiles` records - a built
 * bundle knows no hostname, so the same image runs under any domain.
 *
 * `/tiles` and not a full URL: the app and the tile server are the same origin
 * by construction, because Caddy puts them there. A self-hosted
 * `versatiles serve` lays its styles out at the same paths as the public one,
 * so only the origin differs and every theme stays its own map. */
let tiles = "https://tiles.versatiles.org";

export const setSelfTiles = (self: boolean) => {
  tiles = self ? "/tiles" : "https://tiles.versatiles.org";
};

export const styleUrl = (t: Theme) => `${tiles}/assets/styles/${t.id}/style.json`;

export const loadTheme = (): Theme => {
  try {
    return THEMES.find((t) => t.id === localStorage.getItem(KEY)) ?? THEMES[0]!;
  } catch {
    return THEMES[0]!;
  }
};

export const saveTheme = (t: Theme) => {
  try {
    localStorage.setItem(KEY, t.id);
  } catch {
    // Nothing to do; the choice simply will not survive a reload
  }
};

/** What the overlay draws with, over a basemap of this brightness */
export const ink = (dark: boolean) =>
  dark
    ? { stop: "#cfd8e3", edge: "#0b0f14", nub: "#e8eef7", here: "#38bdf8" }
    : { stop: "#334155", edge: "#f8fafc", nub: "#1e293b", here: "#0284c7" };
