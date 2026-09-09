/** The projection. It is Web Mercator and not something simpler because the
 * basemap under the vehicles is Web Mercator: the overlay has to agree with
 * MapLibre to the pixel, or the buses drive beside the streets. */

export const CENTRE = { lat: 49.842, lon: 24.032 };
export const MIN_ZOOM = 11;
export const MAX_ZOOM = 18;
/** Below this the stop circles are more clutter than information */
export const STOPS_ZOOM = 13.4;

/** The city and its approaches, the same box `wire.py` quantises positions in */
export const BOUNDS: [number, number, number, number] = [
  CENTRE.lon - 0.45,
  CENTRE.lat - 0.3,
  CENTRE.lon + 0.45,
  CENTRE.lat + 0.3,
];

export type View = { lat: number; lon: number; zoom: number };

export const START: View = { ...CENTRE, zoom: 14.3 };

/** MapLibre's tiles are 512 px, so a zoom of z spans 512 * 2^z pixels */
const TILE = 512;

export const mercX = (lon: number) => (lon + 180) / 360;

export const mercY = (lat: number) => {
  const s = Math.sin((lat * Math.PI) / 180);
  return 0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI);
};

/** Screen pixels for a lat/lon, for a north-up unpitched view of `w` by `h`.
 * The two closures share the frame's constants: the draw loop calls them a
 * thousand times a frame and nothing here should be recomputed per point. */
export function screen(view: View, w: number, h: number) {
  const world = TILE * 2 ** view.zoom;
  const cx = mercX(view.lon) * world - w / 2;
  const cy = mercY(view.lat) * world - h / 2;
  return {
    x: (lon: number) => mercX(lon) * world - cx,
    y: (lat: number) => mercY(lat) * world - cy,
  };
}

/** Ground metres one screen pixel covers. The earth's circumference over the
 * width of the world in pixels, narrowed by the latitude Mercator stretches. */
export const metresPerPixel = (lat: number, zoom: number) =>
  (40075016.686 * Math.cos((lat * Math.PI) / 180)) / (TILE * 2 ** zoom);

/** Metres between two points, flat-earth. Over a city 20 km across the error
 * against the great circle is centimetres, and "which stop is nearest" needs
 * far less than that. */
export function metres(a: { lat: number; lon: number }, b: { lat: number; lon: number }) {
  const dy = (a.lat - b.lat) * 111320;
  const dx = (a.lon - b.lon) * 111320 * Math.cos((a.lat * Math.PI) / 180);
  return Math.hypot(dx, dy);
}

const VIEW_KEY = "commuterlviv.view";

export function loadView(): View {
  try {
    const raw = localStorage.getItem(VIEW_KEY);
    // Views stored before the basemap held pixels per degree, not a zoom
    if (raw) {
      const v = JSON.parse(raw) as View;
      if (typeof v.zoom === "number" && typeof v.lat === "number") return v;
    }
  } catch {
    // A corrupt stored view is not worth a blank page
  }
  return START;
}

export function saveView(v: View) {
  try {
    localStorage.setItem(VIEW_KEY, JSON.stringify(v));
  } catch {
    // Nothing to do; the view simply will not survive a reload
  }
}
