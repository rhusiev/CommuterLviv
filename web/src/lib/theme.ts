/** The basemap's look. VersaTiles serves every style at one URL shape over the
 * same tiles, so switching is a `setStyle` and no reload. `dark` drives the
 * overlay's own colours, which are drawn on a canvas above the map. */

export type Theme = {
  id: string;
  name: string;
  dark: boolean;
};

export const THEMES: Theme[] = [
  { id: "shadow", name: "Shadow", dark: true },
  { id: "eclipse", name: "Eclipse", dark: true },
  { id: "graybeard", name: "Graybeard", dark: false },
  { id: "neutrino", name: "Neutrino", dark: false },
  { id: "colorful", name: "Colorful", dark: false },
];

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
    return THEMES.find((t) => t.id === localStorage.getItem(KEY)) ?? THEMES[0]!;
  } catch {
    return THEMES[0]!;
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
    ? { stop: "#cfd8e3", edge: "#0b0f14", nub: "#e8eef7", here: "#38bdf8" }
    : { stop: "#334155", edge: "#f8fafc", nub: "#1e293b", here: "#0284c7" };
