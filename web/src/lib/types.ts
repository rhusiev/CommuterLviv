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

export type Status = {
  variant: string;
  epochs: number;
  tracks: number;
  vehicles: number;
  arrivals: number;
  positions_age: number;
  arrivals_age: number;
  uptime: number;
  polls: number;
  errors: number;
  clients: number;
};
