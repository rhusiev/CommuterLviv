/** The basemap's look. VersaTiles serves every style at one URL shape over the
 * same tiles, so switching is a `setStyle` and no reload. `dark` drives the
 * overlay's own colours, which are drawn on a canvas above the map. */

export type Theme = {
  id: string;
  name: string;
  dark: boolean;
};

export const THEMES: Theme[] = [
  { id: "colorful-dark", name: "Colorful dark", dark: true },
  { id: "natural-dark", name: "Natural dark", dark: true },
  { id: "muted-dark", name: "Muted dark", dark: true },
  { id: "gray-dark", name: "Gray dark", dark: true },
  { id: "colorful", name: "Colorful", dark: false },
  { id: "natural", name: "Natural", dark: false },
  { id: "muted", name: "Muted", dark: false },
  { id: "gray", name: "Gray", dark: false },
];

/** What VersaTiles renamed the styles a browser may still have saved to */
const RENAMED: Record<string, string> = {
  shadow: "gray-dark",
  eclipse: "colorful-dark",
  graybeard: "gray",
  neutrino: "muted",
};

const KEY = "commuterlviv.theme";

/** The public tile server unless `/api/health` says this deployment serves its
 * own, in which case `/tiles` on this origin lays styles out at the same paths. */
let tiles = "https://tiles.versatiles.org";

export const setSelfTiles = (self: boolean) => {
  tiles = self ? "/tiles" : "https://tiles.versatiles.org";
};

export const styleUrl = (t: Theme) => `${tiles}/assets/styles/${t.id}/style.json`;

export const loadTheme = (): Theme => {
  try {
    const id = localStorage.getItem(KEY) ?? "";
    return THEMES.find((t) => t.id === (RENAMED[id] ?? id)) ?? THEMES[0]!;
  } catch {
    return THEMES[0]!;
  }
};

/** An on/off setting kept in the browser, off until set */
export const loadFlag = (key: string): boolean => {
  try {
    return localStorage.getItem(key) === "1";
  } catch {
    return false;
  }
};

export const saveFlag = (key: string, on: boolean) => {
  try {
    localStorage.setItem(key, on ? "1" : "0");
  } catch {
    // The choice simply will not survive a reload
  }
};

export const saveTheme = (t: Theme) => {
  try {
    localStorage.setItem(KEY, t.id);
  } catch {
    // The choice simply will not survive a reload
  }
};

/** What the overlay draws with, over a basemap of this brightness */
export const ink = (dark: boolean) =>
  dark
    ? { stop: "#cfd8e3", edge: "#0b0f14", nub: "#e8eef7", here: "#38bdf8", saved: "#fbbf24" }
    : { stop: "#334155", edge: "#f8fafc", nub: "#1e293b", here: "#0284c7", saved: "#b45309" };
