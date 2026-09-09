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

/** A full style URL still overrides everything, for a self-hosted tile server */
const OVERRIDE = import.meta.env.VITE_MAP_STYLE as string | undefined;

export const styleUrl = (t: Theme) =>
  OVERRIDE ?? `https://tiles.versatiles.org/assets/styles/${t.id}/style.json`;

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
