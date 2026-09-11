export type Route = {
  id: string;
  short: string;
  long: string;

  /** `bus`, `tram` or `trolleybus` - `gtfs.vehicle_type` reads it off the short
   * name, so it is a word and not a GTFS `route_type` number */
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
 * the wire - the socket filter, the stop watch list, the `route` in a frame. */
export type Catalog = { routes: Route[]; stops: Stop[] };

export type RouteSet = {
  id: string;
  name: string;
  routes: string[];
  ord: number;
};

/** A place worth keeping - home, work - as an end of a journey. The name is
 * the identity: saving over a name moves the place rather than making a second
 * one with the same label. */
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

/** The reverse of an `Arrival`: one vehicle, and the stops ahead of it */
export type Call = { stop: number; route: number; t: number };

export type VehicleStops = { t: number; veh: number; stops: Call[] };

/** One unbroken movement of a planned journey. `a` and `b` are catalog stop
 * indexes, or -1 for the door at either end; a walk has no route. `live` says
 * the ride is a vehicle the model can see rather than a timetable entry. */
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

/** One shape the route's trips follow, thinned for the wire. `dir` is the
 * feed's `direction_id`, kept only so the two directions can be told apart. */
export type RouteLine = { dir: number; pts: [number, number][] };

/** `[lat, lon, heading in degrees, 1 where the route also runs the other way
 * along this stretch]`. A list and not an object: a route carries a couple of
 * hundred of them and the keys would outweigh them. */
export type Arrow = [number, number, number, number];

export type RouteShape = { lines: RouteLine[]; arrows: Arrow[] };

/** Parallel to `Catalog.routes`, like everything else on this wire */
export type Shapes = { routes: RouteShape[] };
