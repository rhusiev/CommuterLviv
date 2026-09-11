import { useEffect, useRef, useState } from "react";
import type { Map as MapLibre } from "maplibre-gl";
import WORKER from "maplibre-gl/dist/maplibre-gl-worker.mjs?worker&url";
import {
  BOUNDS,
  loadView,
  MAX_ZOOM,
  metresPerPixel,
  MIN_ZOOM,
  saveView,
  screen,
  STOPS_ZOOM,
  type View,
} from "../lib/geo";
import { sample, type Live } from "../lib/live";
import { build, colour, R, type Sprites } from "../lib/sprites";
import { t } from "../lib/i18n";
import { ink, styleUrl, type Theme } from "../lib/theme";
import type { Catalog, Shapes } from "../lib/types";
import { MOVING_FLAG, STALE_FLAG } from "../lib/wire";

/** The map. MapLibre draws the city and owns every gesture; the vehicles and
 * stops are a 2D canvas on top of it, drawn from MapLibre's own `render` event
 * so the two agree within a frame - an overlay on its own animation frame
 * reads the camera one frame late and the vehicles slide during a fling.
 * No React state changes while it runs: a re-render here is a dropped frame. */

const STOP_R = 3.5;
/** What `live/geometry.py` used, in metres: the arrows arrive that far apart */
const ARROW_SPACING = 220;
/** Below this the whole route is on screen and an arrowhead is five pixels of
 * speckle on the line. The line alone says where the route runs; the zoom that
 * shows a street is the one where which way it runs is a question */
const ARROW_ZOOM = 13;
const HIT = 14;
const TAU = Math.PI * 2;

/** "off" until asked; "denied" once the browser or the user has said no, which
 * is worth showing rather than leaving a button that does nothing */
type Locating = "off" | "waiting" | "on" | "denied";
type Fix = { lat: number; lon: number; accuracy: number };

type Props = {
  catalog: Catalog;
  live: Live;
  stops: number[];
  selected: number | null;
  onPickStop: (i: number | null) => void;
  /** The wire id of the vehicle whose stops ahead are being shown, if any */
  vehicle: number | null;
  onPickVehicle: (id: number | null) => void;
  /** Where the search wants the camera. A new object flies, so asking twice for
   * the same stop flies twice */
  focus: { lat: number; lon: number } | null;
  /** `[west, south, east, north]` the camera should hold, which is how a route
   * is shown: a line the length of the city has no one point to fly to */
  fit: [number, number, number, number] | null;
  /** While the planner is waiting for an end of the journey, a click is that
   * point rather than a choice of stop */
  picking: boolean;
  onPickPoint: (lat: number, lon: number) => void;
  /** The journey's two ends, drawn as lettered pins */
  marks: { lat: number; lon: number; label: string }[];
  /** Every route's geometry, once something has asked for it */
  shapes: Shapes | null;
  /** Which routes to draw a line for, and which one - if any - to put the
   * direction arrows on. Arrows are for the single route being looked at; a
   * city's worth of them would be a texture, not information */
  lines: number[];
  arrowed: number | null;
  theme: Theme;
};

/** One arrowhead sitting on the line, pointing along `(cos, sin)`. Drawn in the
 * page's ink rather than the route's colour: it is a notch cut out of the line,
 * and a coloured head on a line of the same colour is nothing at all. A stretch
 * the route runs both ways gets two of these back to back. */
function head(g: CanvasRenderingContext2D, x: number, y: number, cos: number, sin: number) {
  g.beginPath();
  g.moveTo(x + cos * 7, y + sin * 7);
  g.lineTo(x - cos * 3 - sin * 4.5, y - sin * 3 + cos * 4.5);
  g.lineTo(x - cos * 3 + sin * 4.5, y - sin * 3 - cos * 4.5);
  g.closePath();
  g.fill();
}

const viewOf = (m: MapLibre): View => {
  const c = m.getCenter();
  return { lat: c.lat, lon: c.lng, zoom: m.getZoom() };
};

export function MapCanvas({
  catalog,
  live,
  stops,
  selected,
  onPickStop,
  vehicle,
  onPickVehicle,
  focus,
  fit,
  picking,
  onPickPoint,
  marks,
  shapes,
  lines,
  arrowed,
  theme,
}: Props) {
  const box = useRef<HTMLDivElement>(null);
  const under = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const sprites = useRef<Sprites | null>(null);
  const shown = useRef(stops);
  const pick = useRef(selected);
  const onPick = useRef(onPickStop);
  const onPickVeh = useRef(onPickVehicle);
  const chosen = useRef(vehicle);
  const paint = useRef(ink(theme.dark));
  const style = useRef(styleUrl(theme));
  const held = useRef<MapLibre | null>(null);
  const here = useRef<Fix | null>(null);
  const pickPoint = useRef(onPickPoint);
  const picks = useRef(picking);
  const pins = useRef(marks);
  const geometry = useRef(shapes);
  const drawn = useRef(lines);
  const arrows = useRef(arrowed);
  const [locating, setLocating] = useState<Locating>("off");

  shown.current = stops;
  pick.current = selected;
  onPick.current = onPickStop;
  onPickVeh.current = onPickVehicle;
  chosen.current = vehicle;
  paint.current = ink(theme.dark);
  pickPoint.current = onPickPoint;
  picks.current = picking;
  pins.current = marks;
  geometry.current = shapes;
  drawn.current = lines;
  arrows.current = arrowed;

  useEffect(() => {
    const el = canvas.current!;
    const g = el.getContext("2d")!;
    let map: MapLibre | null = null;
    let gone = false;
    let w = 0;
    let h = 0;

    const resize = () => {
      // The observer can fire once more after React has cleared the ref
      const rect = box.current?.getBoundingClientRect();
      if (!rect) return;
      const dpr = devicePixelRatio;
      w = rect.width;
      h = rect.height;
      el.width = Math.round(w * dpr);
      el.height = Math.round(h * dpr);
      el.style.width = `${w}px`;
      el.style.height = `${h}px`;
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      if (!sprites.current || sprites.current.dpr !== dpr) {
        sprites.current = build(catalog.routes, dpr);
      }
      // The map is created a dynamic import later than this box exists, and a
      // map built against a box of no height keeps MapLibre's 400x300 default
      map?.resize();
    };
    const observer = new ResizeObserver(resize);
    observer.observe(box.current!);
    resize();

    const draw = () => {
      const m = map!;
      const p = screen(viewOf(m), w, h);
      const now = performance.now();
      const c = paint.current;

      g.clearRect(0, 0, w, h);

      // Under everything else: a route is the background a rider reads the
      // vehicles against, and a line over a badge hides the number
      const geo = geometry.current;
      if (geo) {
        g.lineJoin = "round";
        g.lineCap = "round";
        for (const i of drawn.current) {
          const shape = geo.routes[i];
          const route = catalog.routes[i];
          if (!shape || !route) continue;
          const path = new Path2D();
          for (const line of shape.lines) {
            let first = true;
            for (const [lat, lon] of line.pts) {
              const x = p.x(lon);
              const y = p.y(lat);
              if (first) path.moveTo(x, y);
              else path.lineTo(x, y);
              first = false;
            }
          }
          // A casing under the colour, so a line crossing another is still one
          // line and not a knot of the same width
          g.strokeStyle = c.edge;
          g.lineWidth = 6;
          g.globalAlpha = 0.5;
          g.stroke(path);
          g.strokeStyle = colour(route.short, route.type);
          g.lineWidth = 3.5;
          g.globalAlpha = drawn.current.length > 1 ? 0.75 : 1;
          g.stroke(path);
          g.globalAlpha = 1;
        }

        const one = arrows.current;
        const shape = one === null ? null : geo.routes[one];
        if (shape && m.getZoom() >= ARROW_ZOOM) {
          // The server spaces arrows every 220 m along the line, which at the
          // zoom that holds a whole route is five pixels: drawn as they come
          // the line reads as a dashed one. They arrive in order along each
          // shape, so every nth is still evenly spaced - just further apart
          const step = Math.max(
            1,
            Math.ceil((60 * metresPerPixel(m.getCenter().lat, m.getZoom())) / ARROW_SPACING),
          );
          g.fillStyle = c.edge;
          for (let k = 0; k < shape.arrows.length; k += step) {
            const [lat, lon, heading, both] = shape.arrows[k]!;
            const x = p.x(lon);
            const y = p.y(lat);
            if (x < -12 || y < -12 || x > w + 12 || y > h + 12) continue;
            const a = ((heading - 90) * Math.PI) / 180;
            const cos = Math.cos(a);
            const sin = Math.sin(a);
            // Two heads back to back would sit on top of each other and read as
            // a diamond, so each backs off along the line by its own length
            const off = both ? 9 : 0;
            head(g, x + cos * off, y + sin * off, cos, sin);
            if (both) head(g, x - cos * off, y - sin * off, -cos, -sin);
          }
        }
      }

      if (m.getZoom() >= STOPS_ZOOM) {
        // One path for every stop: a fill and a stroke, not two per circle
        const ring = new Path2D();
        for (const i of shown.current) {
          const s = catalog.stops[i]!;
          const x = p.x(s.lon);
          const y = p.y(s.lat);
          if (x < -8 || y < -8 || x > w + 8 || y > h + 8) continue;
          ring.moveTo(x + STOP_R, y);
          ring.arc(x, y, STOP_R, 0, TAU);
        }
        g.fillStyle = c.stop;
        g.strokeStyle = c.edge;
        g.lineWidth = 1.5;
        g.fill(ring);
        g.stroke(ring);

        const sel = pick.current;
        if (sel !== null && catalog.stops[sel]) {
          const s = catalog.stops[sel]!;
          g.beginPath();
          g.arc(p.x(s.lon), p.y(s.lat), STOP_R + 4, 0, TAU);
          g.lineWidth = 2;
          g.strokeStyle = c.nub;
          g.stroke();
        }
      }

      const fix = here.current;
      if (fix) {
        const x = p.x(fix.lon);
        const y = p.y(fix.lat);
        // The accuracy ring is the honest part of this: a 300 m fix indoors
        // drawn as a 6 px dot claims a precision the phone never had
        const ring = fix.accuracy / metresPerPixel(fix.lat, m.getZoom());
        if (ring > STOP_R * 2) {
          g.beginPath();
          g.arc(x, y, ring, 0, TAU);
          g.globalAlpha = 0.12;
          g.fillStyle = c.here;
          g.fill();
          g.globalAlpha = 1;
        }
        // A 6 px dot is the same mark as a stop and loses to forty vehicles
        // around it. The halo is what makes it findable without panning: a soft
        // disc there at every zoom, even when the accuracy ring is too small
        g.beginPath();
        g.arc(x, y, 15, 0, TAU);
        g.globalAlpha = 0.22;
        g.fillStyle = c.here;
        g.fill();
        g.globalAlpha = 0.5;
        g.lineWidth = 1.5;
        g.strokeStyle = c.here;
        g.stroke();
        g.globalAlpha = 1;
        g.beginPath();
        g.arc(x, y, 6, 0, TAU);
        g.fillStyle = c.here;
        g.fill();
        g.lineWidth = 3;
        g.strokeStyle = c.edge;
        g.stroke();
      }

      for (const mark of pins.current) {
        const x = p.x(mark.lon);
        const y = p.y(mark.lat);
        g.beginPath();
        g.arc(x, y, 9, 0, TAU);
        g.fillStyle = c.nub;
        g.fill();
        g.lineWidth = 2;
        g.strokeStyle = c.edge;
        g.stroke();
        g.fillStyle = c.edge;
        g.font = "bold 11px system-ui, sans-serif";
        g.textAlign = "center";
        g.textBaseline = "middle";
        g.fillText(mark.label, x, y);
      }

      const badges = sprites.current!.badges;
      for (const [id, veh] of live.vehicles) {
        const [lat, lon, heading] = sample(veh, now);
        const x = p.x(lon);
        const y = p.y(lat);
        if (x < -R || y < -R || x > w + R || y > h + R) continue;

        // The direction wedge sits on the rim rather than inside it, so the
        // number stays readable at any angle. It is drawn whether or not the
        // vehicle is moving - which way it faces is known either way, and a
        // marker with no wedge left no way to tell one end of the route from
        // the other. Solid means under way; an outline means standing, so the
        // wedge says where it will go without claiming it is going there now
        g.globalAlpha = veh.flags & STALE_FLAG ? 0.45 : 1;
        const a = ((heading - 90) * Math.PI) / 180;
        const cos = Math.cos(a);
        const sin = Math.sin(a);
        g.beginPath();
        g.moveTo(x + cos * (R + 5), y + sin * (R + 5));
        g.lineTo(x + cos * R - sin * 5, y + sin * R + cos * 5);
        g.lineTo(x + cos * R + sin * 5, y + sin * R - cos * 5);
        g.closePath();
        if (veh.flags & MOVING_FLAG) {
          g.fillStyle = c.nub;
          g.fill();
        } else {
          g.lineWidth = 1.5;
          g.lineJoin = "round";
          g.strokeStyle = c.nub;
          g.stroke();
        }

        const badge = badges[veh.route];
        if (!badge) {
          g.globalAlpha = 1;
          continue;
        }
        g.drawImage(badge, x - R, y - R, R * 2, R * 2);
        if (id === chosen.current) {
          g.beginPath();
          g.arc(x, y, R + 3, 0, TAU);
          g.lineWidth = 2;
          g.strokeStyle = c.nub;
          g.stroke();
        }
        g.globalAlpha = 1;
      }

      // The vehicles move between camera changes, so every frame is wanted
      m.triggerRepaint();
    };

    // Both the library and its stylesheet load only once there is a map to
    // show: a quarter of a megabyte should not sit in front of the sign-in form
    void Promise.all([import("maplibre-gl"), import("maplibre-gl/dist/maplibre-gl.css")]).then(([{ Map, NavigationControl, setWorkerUrl }]) => {
      if (gone) return;
      // Left alone maplibre looks for `maplibre-gl-worker.mjs` beside its own
      // module: the dev optimiser leaves that file mute and the build never
      // emits it, and either way no tile is fetched and nothing is logged
      setWorkerUrl(WORKER);
      const v = loadView();
      map = new Map({
        container: under.current!,
        style: style.current,
        center: [v.lon, v.lat],
        zoom: v.zoom,
        minZoom: MIN_ZOOM,
        maxZoom: MAX_ZOOM,
        maxBounds: BOUNDS,
        renderWorldCopies: false,
        dragRotate: false,
        pitchWithRotate: false,
        touchPitch: false,
        attributionControl: { compact: true },
        canvasContextAttributes: { antialias: false, powerPreference: "high-performance" },
      });
      map.touchZoomRotate.disableRotation();
      map.keyboard.disableRotation();
      // No compass, because there is no rotation to undo: the vehicle overlay is
      // a second canvas drawn from the camera's centre and zoom alone, so the
      // map is held at north on purpose
      map.addControl(new NavigationControl({ showCompass: false }), "bottom-right");

      // A tile that will not load is a fact about the network, not a fault in
      // the app, and the vehicles stay on screen without it
      map.on("error", (e) => console.warn("basemap:", e.error?.message ?? e));
      map.on("moveend", () => saveView(viewOf(map!)));
      map.on("click", (e) => {
        // While an end of a journey is being set, every click is that point:
        // the nearest stop is not what was asked for, and a door is rarely one
        if (picks.current) {
          pickPoint.current(e.lngLat.lat, e.lngLat.lng);
          return;
        }
        const p = screen(viewOf(map!), w, h);
        // Vehicles first: they are drawn over the stops and are the larger
        // target, so a tap that lands on a badge meant the badge
        let veh: number | null = null;
        let vehD = R * R;
        const now = Date.now() / 1000;
        for (const [id, v] of live.vehicles) {
          const [lat, lon] = sample(v, now);
          const dx = p.x(lon) - e.point.x;
          const dy = p.y(lat) - e.point.y;
          const d = dx * dx + dy * dy;
          if (d < vehD) {
            vehD = d;
            veh = id;
          }
        }
        if (veh !== null) {
          onPickVeh.current(veh);
          onPick.current(null);
          return;
        }

        let best: number | null = null;
        let bestD = HIT * HIT;
        for (const i of shown.current) {
          const s = catalog.stops[i]!;
          const dx = p.x(s.lon) - e.point.x;
          const dy = p.y(s.lat) - e.point.y;
          const d = dx * dx + dy * dy;
          if (d < bestD) {
            bestD = d;
            best = i;
          }
        }
        onPickVeh.current(null);
        onPick.current(best);
      });
      map.on("render", draw);
      held.current = map;
      resize();
      if (import.meta.env.DEV) (window as { lvivMap?: MapLibre }).lvivMap = map;
    });

    return () => {
      gone = true;
      observer.disconnect();
      held.current = null;
      map?.remove();
    };
  }, [catalog, live]);

  // A theme change is a new basemap under the same camera, not a new map: the
  // overlay, the gestures and the view all survive `setStyle`
  useEffect(() => {
    const url = styleUrl(theme);
    if (url === style.current) return;
    style.current = url;
    held.current?.setStyle(url);
  }, [theme]);

  // Same waiting as `focus`, and the same reason: a route opened from a link
  // is asked for before the map exists
  useEffect(() => {
    if (!fit) return;
    let timer = 0;
    const go = () => {
      const m = held.current;
      if (!m) {
        timer = window.setTimeout(go, 100);
        return;
      }
      m.fitBounds([fit[0], fit[1], fit[2], fit[3]], { padding: 48, duration: 800 });
    };
    go();
    return () => clearTimeout(timer);
  }, [fit]);

  // The map may not exist yet when the first focus arrives - a search hit
  // during the dynamic import - so this waits for it rather than dropping it
  useEffect(() => {
    if (!focus) return;
    let timer = 0;
    const go = () => {
      const m = held.current;
      if (!m) {
        timer = window.setTimeout(go, 100);
        return;
      }
      m.flyTo({ center: [focus.lon, focus.lat], zoom: Math.max(m.getZoom(), 16), speed: 1.6 });
    };
    go();
    return () => clearTimeout(timer);
  }, [focus]);

  // The effect turns on the watch and must not restart when the first fix
  // turns "waiting" into "on", so it hangs on the boolean and not the state
  const tracking = locating === "waiting" || locating === "on";
  useEffect(() => {
    if (!tracking) return;
    // Only the first fix moves the camera; after that the dot moves and the
    // view stays where the user put it
    let first = true;
    const watch = navigator.geolocation.watchPosition(
      (pos) => {
        const { latitude, longitude, accuracy } = pos.coords;
        here.current = { lat: latitude, lon: longitude, accuracy };
        if (first) {
          first = false;
          held.current?.flyTo({ center: [longitude, latitude], zoom: 16, speed: 1.6 });
        }
        setLocating("on");
      },
      () => {
        here.current = null;
        setLocating("denied");
      },
      { enableHighAccuracy: true, maximumAge: 10000 },
    );
    return () => navigator.geolocation.clearWatch(watch);
  }, [tracking]);

  return (
    <div ref={box} className="absolute inset-0 touch-none">
      {/* MapLibre's stylesheet makes its container `position: relative`, and it
          loads after Tailwind, so `inset-0` alone would leave it 0 px tall */}
      <div ref={under} className="absolute h-full w-full" />
      <canvas ref={canvas} className="pointer-events-none absolute inset-0" />
      {/* Below the floating bar rather than beside it: the bar spans the top */}
      <button
        onClick={() => {
          if (locating === "on" && here.current) {
            const f = here.current;
            held.current?.flyTo({ center: [f.lon, f.lat], zoom: 16, speed: 1.6 });
          } else if (locating !== "denied") {
            setLocating("waiting");
          }
        }}
        title={locating === "denied" ? t.noLocation : t.whereAmI}
        className={`fab absolute right-3 top-19 z-10 ${
          locating === "denied"
            ? "text-slate-600"
            : locating === "on"
              ? "text-accent"
              : "text-slate-300 hover:text-slate-100"
        }`}
      >
        <svg viewBox="0 0 24 24" className="size-5" fill="none" stroke="currentColor" strokeWidth="2">
          <circle cx="12" cy="12" r="4" />
          <circle cx="12" cy="12" r="8.5" strokeDasharray="3 3" />
          <path d="M12 1v3M12 20v3M1 12h3M20 12h3" strokeLinecap="round" />
        </svg>
      </button>
    </div>
  );
}
