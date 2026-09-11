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
};

export type Journey = { dep: number; arr: number; rides: number; live: boolean; legs: Leg[] };

export type Plan = { t: number; options: Journey[] };

/** `dir` is the feed's `direction_id`, kept only to tell the two apart */
export type RouteLine = { dir: number; pts: [number, number][] };

/** `[lat, lon, heading in degrees, 1 where the route also runs the other way
 * along this stretch]` */
export type Arrow = [number, number, number, number];

export type RouteShape = { lines: RouteLine[]; arrows: Arrow[] };

/** Parallel to `Catalog.routes` */
export type Shapes = { routes: RouteShape[] };
