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

/** `planned`: the vehicle is still finishing its previous trip, so `t` is its
 * timetabled departure or its turnaround, whichever is later */
export type Arrival = { route: number; veh: number; t: number; planned?: boolean };

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
  /** `[lat, lon]` along the footpath or the ridden stretch */
  pts?: [number, number][];
  /** Catalog stops a ride calls at on the way, in order; absent from an older
   *  service */
  stops?: number[];
  /** Other ways to the door from where the ride boards, soonest first */
  backups?: Backup[];
};

/** Another way to the door from where a ride boards: the rides it takes, the
 * first leaving from there, when it reaches the door and the seconds it walks.
 * A ride `planned` is on a vehicle the journey rides too, further along.
 * `option` is the place in the plan's options of the one riding exactly these
 * rides, or -1; an older service leaves it out */
export type Backup = {
  rides: { route: number; dep: number; arr: number; a: number; b: number; live: boolean; planned: boolean }[];
  arr: number;
  walk: number;
  option?: number;
};

/** The journey's confidence is the weakest of its rides; `backup` is how many
 * other ways to the door its weakest ride has, as in `Leg.backups`, leaving
 * out those riding the journey's own vehicles */
export type Journey = {
  dep: number;
  arr: number;
  rides: number;
  live: boolean;
  confidence: Confidence;
  backup: number;
  legs: Leg[];
};

/** `report` names the search for `api.report`, for half an hour */
export type Plan = { t: number; options: Journey[]; report?: string };

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
