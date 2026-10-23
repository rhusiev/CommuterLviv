/** Web Mercator, because the basemap is: the overlay has to agree with MapLibre
 * to the pixel or the vehicles drive beside the streets. */

import { readJson, writeJson } from "./storage";
import { BOX } from "./wire";

/** Rynok Square, which the server's place search also ranks from */
export const CENTRE = { lat: 49.8419, lon: 24.0315 };
export const MIN_ZOOM = 11;
export const MAX_ZOOM = 18;
/** Below this the stop circles are more clutter than information */
export const STOPS_ZOOM = 13.4;
/** From here every stop is drawn and can be clicked, the ones no route on the
 * map calls at faint: close enough to read the street a stop is on */
export const ALL_STOPS_ZOOM = 16;

/** The stops a click can pick at `zoom`: the ones on the map's routes, and
 * from `ALL_STOPS_ZOOM` every other one too */
export const pickable = (zoom: number, stops: number[], faint: number[]) =>
  zoom >= ALL_STOPS_ZOOM ? stops.concat(faint) : stops;

/** How far the map pans past the box vehicles can be in, as a share of the
 * box: enough to bring its edge to the middle of a wide screen */
const PAN_ROOM = 0.5;

/** Where the map can be panned, as `[west, south, east, north]` */
export const BOUNDS = ((): [number, number, number, number] => {
  const [west, south, east, north] = BOX;
  const lon = (east - west) * PAN_ROOM;
  const lat = (north - south) * PAN_ROOM;
  return [west - lon, south - lat, east + lon, north + lat];
})();

export type View = { lat: number; lon: number; zoom: number };

export const START: View = { ...CENTRE, zoom: 14.3 };

/** MapLibre's tiles are 512 px, so a zoom of z spans 512 * 2^z pixels - the
 * scale the app's 256 px tiles reach at z + 1, which its thresholds allow for
 * (`webZoomOffset`) */
const TILE = 512;

export const mercX = (lon: number) => (lon + 180) / 360;

export const mercY = (lat: number) => {
  const s = Math.sin((lat * Math.PI) / 180);
  return 0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI);
};

/** Screen pixels for a lat/lon, for a north-up unpitched view of `w` by `h`.
 * The two closures share the frame's constants: the draw loop calls them
 * thousands of times a frame. */
export function screen(view: View, w: number, h: number) {
  const world = TILE * 2 ** view.zoom;
  const cx = mercX(view.lon) * world - w / 2;
  const cy = mercY(view.lat) * world - h / 2;
  return {
    x: (lon: number) => mercX(lon) * world - cx,
    y: (lat: number) => mercY(lat) * world - cy,
  };
}

/** Ground metres one screen pixel covers */
export const metresPerPixel = (lat: number, zoom: number) =>
  (40075016.686 * Math.cos((lat * Math.PI) / 180)) / (TILE * 2 ** zoom);

/** Metres between two points, flat-earth: over a city 20 km across the error
 * against the great circle is centimetres. */
export function metres(a: { lat: number; lon: number }, b: { lat: number; lon: number }) {
  const dy = (a.lat - b.lat) * 111320;
  const dx = (a.lon - b.lon) * 111320 * Math.cos((a.lat * Math.PI) / 180);
  return Math.hypot(dx, dy);
}

const VIEW_KEY = "commuterlviv.view";

export function loadView(): View {
  const v = readJson<View>(VIEW_KEY);
  return typeof v?.zoom === "number" && typeof v.lat === "number" ? v : START;
}

export function saveView(v: View) {
  writeJson(VIEW_KEY, v);
}
