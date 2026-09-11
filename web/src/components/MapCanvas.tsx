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
import { sync } from "../lib/layers";
import { sample, type Live } from "../lib/live";
import type { Pace } from "../lib/traffic";
import { build, colour, R, type Sprites } from "../lib/sprites";
import { t } from "../lib/i18n";
import { ink, styleUrl, type Theme } from "../lib/theme";
import type { Catalog, Shapes } from "../lib/types";
import { MOVING_FLAG, STALE_FLAG } from "../lib/wire";

/** The vehicle/stop overlay is a 2D canvas drawn from MapLibre's own `render`
 * event, so the two agree within a frame; drawing on a separate animation frame
 * reads the camera one frame late. No React state changes during the draw. */

const STOP_R = 3.5;
const HIT = 14;
const TAU = Math.PI * 2;

type Locating = "off" | "waiting" | "on" | "denied";
type Fix = { lat: number; lon: number; accuracy: number };

type Props = {
  catalog: Catalog;
  live: Live;
  stops: number[];
  selected: number | null;
  onPickStop: (i: number | null) => void;
  vehicle: number | null;
  onPickVehicle: (id: number | null) => void;
  /** Compared by identity, so a new object flies even to the same place */
  focus: { lat: number; lon: number } | null;
  /** `[west, south, east, north]` */
  fit: [number, number, number, number] | null;
  /** A click sets a journey end instead of choosing a stop */
  picking: boolean;
  onPickPoint: (lat: number, lon: number) => void;
  marks: { lat: number; lon: number; label: string }[];
  shapes: Shapes | null;
  lines: number[];
  /** The route whose direction of travel is marked with chevrons */
  directed: number | null;
  traffic: Pace | null;
  theme: Theme;
};

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
  directed,
  traffic,
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
  /** What the basemap's own layers draw, read again on every `styledata` */
  const beneath = useRef({ shapes, directed, traffic, dark: theme.dark });
  const [locating, setLocating] = useState<Locating>("off");
  const [ready, setReady] = useState(false);

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
  beneath.current = { shapes, directed, traffic, dark: theme.dark };

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
      // A map built against a box of no height keeps MapLibre's 400x300 default
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

      // Route lines first: everything else is drawn over them
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
          // A casing under the colour keeps crossing lines readable
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
      }

      if (m.getZoom() >= STOPS_ZOOM) {
        // One path for every stop: one fill and one stroke, not two per circle
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
        const ring = fix.accuracy / metresPerPixel(fix.lat, m.getZoom());
        if (ring > STOP_R * 2) {
          g.beginPath();
          g.arc(x, y, ring, 0, TAU);
          g.globalAlpha = 0.12;
          g.fillStyle = c.here;
          g.fill();
          g.globalAlpha = 1;
        }
        // Halo at every zoom: the 6 px dot alone is the same mark as a stop
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

        // Direction wedge on the rim: solid when under way, outlined when standing
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

      // Vehicles move between camera changes, so keep asking for frames
      m.triggerRepaint();
    };

    void Promise.all([import("maplibre-gl"), import("maplibre-gl/dist/maplibre-gl.css")]).then(([{ Map, NavigationControl, setWorkerUrl }]) => {
      if (gone) return;
      // Left alone maplibre looks for `maplibre-gl-worker.mjs` beside its own
      // module, which neither the dev optimiser nor the build serves: no tile
      // is then fetched and nothing is logged
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
      // No compass: the overlay projects from centre and zoom alone, so
      // rotation is disabled and the map is held at north
      map.addControl(new NavigationControl({ showCompass: false }), "bottom-right");

      map.on("error", (e) => console.warn("basemap:", e.error?.message ?? e));
      map.on("moveend", () => saveView(viewOf(map!)));
      map.on("click", (e) => {
        if (picks.current) {
          pickPoint.current(e.lngLat.lat, e.lngLat.lng);
          return;
        }
        const p = screen(viewOf(map!), w, h);
        // Vehicles first: they are drawn over the stops
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
      // Every style swap throws the sources and layers away and leaves this the
      // only notice of it, so the layers are rebuilt from here rather than from
      // the effect that asked for the new style
      map.on("styledata", () => sync(map!, beneath.current));
      held.current = map;
      setReady(true);
      resize();
      if (import.meta.env.DEV) (window as { lvivMap?: MapLibre }).lvivMap = map;
    });

    return () => {
      gone = true;
      observer.disconnect();
      held.current = null;
      setReady(false);
      map?.remove();
    };
  }, [catalog, live]);

  useEffect(() => {
    if (ready && held.current) sync(held.current, { shapes, directed, traffic, dark: theme.dark });
  }, [ready, shapes, directed, traffic, theme]);

  // `setStyle` keeps the camera, the gestures and the overlay
  useEffect(() => {
    const url = styleUrl(theme);
    if (url === style.current) return;
    style.current = url;
    held.current?.setStyle(url);
  }, [theme]);

  // The map is created a dynamic import late, so the first fit or focus can
  // arrive before it exists: poll rather than drop it
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

  // A boolean and not the state: the watch must not restart when the first fix
  // turns "waiting" into "on"
  const tracking = locating === "waiting" || locating === "on";
  useEffect(() => {
    if (!tracking) return;
    // Only the first fix moves the camera
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
