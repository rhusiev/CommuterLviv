export type Route = {
  id: string;
  short: string;
  long: string;

  /** `bus`, `tram` or `trolleybus` - a word, not a GTFS `route_type` number */
  type: string;
};

export type Stop = {
  id: string;
  name: string;
  code: string;
  lat: number;
  lon: number;
  routes: number[];
};

/** Routes and stops are addressed by their index in these arrays everywhere on
 * the wire: the socket filter, the stop watch list, the `route` in a frame. */
export type Catalog = { routes: Route[]; stops: Stop[] };

export type RouteSet = {
  id: string;
  name: string;
  routes: string[];
  ord: number;
};

/** The name is the identity: saving over one moves the place */
export type Place = { name: string; lat: number; lon: number };

export type Sets = {
  sets: RouteSet[];
  active: string | null;
  pins: string[];
  places: Place[];
};

export type Me = { username: string; sets: Sets };

export type Arrival = { route: number; veh: number; t: number };

export type Arrivals = { t: number; stops: Record<string, Arrival[]> };

export type Call = { stop: number; route: number; t: number };

export type VehicleStops = { t: number; veh: number; stops: Call[] };

/** What a ride rests on: a tracked vehicle, the timetable, or the timetable on
 * a line nothing has been seen running on lately */
export type Confidence = "live" | "schedule" | "quiet";

/** `a` and `b` are catalog stop indexes, or -1 for the door at either end; a
 * walk has no route. `live` marks a tracked vehicle rather than a timetable. */
export type Leg = {
  kind: "walk" | "ride";
  dep: number;
  arr: number;
  a: number;
  b: number;
  route?: number;
  veh?: number | null;
  live?: boolean;
  confidence?: Confidence;
};

/** The journey's confidence is the weakest of its rides */
export type Journey = {
  dep: number;
  arr: number;
  rides: number;
  live: boolean;
  confidence: Confidence;
  legs: Leg[];
};

export type Plan = { t: number; options: Journey[] };

/** `dir` is the feed's `direction_id`, kept only to tell the two apart */
export type RouteLine = { dir: number; pts: [number, number][] };

export type RouteShape = { lines: RouteLine[] };

/** Parallel to `Catalog.routes` */
export type Shapes = { routes: RouteShape[] };

/** A place found by name in OpenStreetMap. `where` is the line under the name,
 * enough to tell two identical names apart; `kind` is the OSM value, so a shop
 * and a street can be told apart. */
export type Found = {
  name: string;
  where: string;
  lat: number;
  lon: number;
  kind: string | null;
};

/** One polyline per stretch of street with transit on it. Fixed for the life of
 * the service, so it is fetched once and kept. */
export type Streets = { lines: [number, number][][] };

/** Parallel to `Streets.lines`: actual over timetabled travel time on that
 * stretch, above 1 being slower than scheduled. Null is too little seen there
 * to say anything, and is drawn as nothing. */
export type Traffic = { t: number; ratio: (number | null)[] };
