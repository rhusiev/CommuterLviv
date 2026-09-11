import type { GeoJSONSource, Map as MapLibre } from "maplibre-gl";
import type { Feature, FeatureCollection, LineString } from "geojson";
import { ink } from "./theme";
import { RAMP, type Pace } from "./traffic";
import type { Shapes } from "./types";

/** What the basemap itself draws, under the overlay canvas: how fast the
 * streets are running, and which way the open route goes.
 *
 * Both are GeoJSON sources whose data is replaced in place, so a new set of
 * traffic numbers costs one `setData` and no layer churn. `setStyle` throws
 * every source, layer and image away, so `sync` builds whatever is missing and
 * is called again on `styledata`. */

const TRAFFIC = "commuterlviv-traffic";
const DIR = "commuterlviv-dir";
const CHEVRON = "commuterlviv-chevron";

/** Pixels either side of the centre line where a route runs both ways. Wide
 * enough that the two rows of chevrons do not read as one dashed line. */
const SPLIT = 5;

const EMPTY: FeatureCollection<LineString> = { type: "FeatureCollection", features: [] };

/** Drawn pointing along +x, which is the way a line-placed symbol is rotated */
function chevron(colour: string): ImageData {
  const el = document.createElement("canvas");
  el.width = el.height = 28;
  const g = el.getContext("2d")!;
  g.scale(2, 2);
  g.strokeStyle = colour;
  g.lineWidth = 2.5;
  g.lineCap = "round";
  g.lineJoin = "round";
  g.beginPath();
  g.moveTo(4, 3);
  g.lineTo(10, 7);
  g.lineTo(4, 11);
  g.stroke();
  return g.getImageData(0, 0, el.width, el.height);
}

const along = (pts: [number, number][]): LineString => ({
  type: "LineString",
  coordinates: pts.map(([lat, lon]) => [lon, lat]),
});

function directions(shapes: Shapes | null, route: number | null): FeatureCollection<LineString> {
  const shape = shapes && route !== null ? shapes.routes[route] : null;
  if (!shape) return EMPTY;
  // Only a stretch with both directions is pushed aside; a one-way line keeps
  // its chevrons on the centre, where the wings show either side of it
  const both =
    shape.lines.some((l) => l.dir === 0) && shape.lines.some((l) => l.dir === 1);
  return {
    type: "FeatureCollection",
    features: shape.lines.map((line) => ({
      type: "Feature",
      properties: { off: both ? (line.dir === 1 ? -SPLIT : SPLIT) : 0 },
      geometry: along(line.pts),
    })),
  };
}

function pace(now: Pace | null): FeatureCollection<LineString> {
  if (!now) return EMPTY;
  const features: Feature<LineString>[] = [];
  now.lines.forEach((pts, i) => {
    const r = now.ratio[i];
    // Too little seen on this stretch to say anything, so it is not drawn
    if (r === null || r === undefined || pts.length < 2) return;
    features.push({ type: "Feature", properties: { r }, geometry: along(pts) });
  });
  return { type: "FeatureCollection", features };
}

function feed(map: MapLibre, id: string, data: FeatureCollection<LineString>) {
  const had = map.getSource(id) as GeoJSONSource | undefined;
  if (had) had.setData(data);
  else map.addSource(id, { type: "geojson", data });
}

type State = {
  shapes: Shapes | null;
  directed: number | null;
  traffic: Pace | null;
  dark: boolean;
};

export function sync(map: MapLibre, state: State) {
  if (!map.isStyleLoaded()) return;

  feed(map, TRAFFIC, pace(state.traffic));
  feed(map, DIR, directions(state.shapes, state.directed));

  if (!map.hasImage(CHEVRON)) {
    map.addImage(CHEVRON, chevron(ink(state.dark).nub), { pixelRatio: 2 });
  }

  // Added in one pass, so traffic stays under the route it might be read with
  if (!map.getLayer(TRAFFIC)) {
    map.addLayer({
      id: TRAFFIC,
      type: "line",
      source: TRAFFIC,
      layout: { "line-cap": "round", "line-join": "round" },
      paint: {
        "line-width": ["interpolate", ["linear"], ["zoom"], 11, 2.5, 16, 7],
        "line-opacity": 0.85,
        "line-color": ["interpolate", ["linear"], ["get", "r"], ...RAMP.flat()],
      },
    });
  }
  if (!map.getLayer(DIR)) {
    map.addLayer({
      id: DIR,
      type: "line",
      source: DIR,
      paint: {
        "line-width": 1,
        "line-opacity": 0.35,
        "line-offset": ["get", "off"],
        "line-color": ink(state.dark).nub,
      },
    });
    map.addLayer({
      id: CHEVRON,
      type: "symbol",
      source: DIR,
      layout: {
        "icon-image": CHEVRON,
        "symbol-placement": "line",
        // Far enough apart to stay one glyph rather than a texture when the
        // whole line is on screen
        "symbol-spacing": ["interpolate", ["linear"], ["zoom"], 11, 130, 16, 70],
        "icon-rotation-alignment": "map",
        "icon-allow-overlap": true,
        "icon-ignore-placement": true,
        "icon-offset": [
          "case",
          [">", ["get", "off"], 0],
          ["literal", [0, SPLIT]],
          ["<", ["get", "off"], 0],
          ["literal", [0, -SPLIT]],
          ["literal", [0, 0]],
        ],
      },
    });
  }
}
