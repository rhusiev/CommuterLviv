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

export type Sets = { sets: RouteSet[]; active: string | null; pins: string[] };

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
