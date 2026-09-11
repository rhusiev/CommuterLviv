import type {
  Arrivals,
  Call,
  Catalog,
  Found,
  Me,
  Place,
  Plan,
  RouteSet,
  Sets,
  Shapes,
  Streets,
  Traffic,
} from "./types";

/** Same origin by default: Vite proxies `/api` and `/ws` in development, so the
 * session cookie is first-party either way. */
export const BASE = import.meta.env.VITE_API_URL ?? "";

type Failure = { error?: string; retry?: number };

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly retry?: number,
  ) {
    super(message);
  }
}

function csrf(): string {
  // The service prefixes the name with __Host- when it sets secure cookies
  for (const part of document.cookie.split("; ")) {
    const eq = part.indexOf("=");
    const name = part.slice(0, eq);
    if (name === "lp_csrf" || name === "__Host-lp_csrf") return part.slice(eq + 1);
  }
  return "";
}

async function call<T>(path: string, options: RequestInit = {}): Promise<T> {
  const unsafe = options.method !== undefined && options.method !== "GET";
  const res = await fetch(BASE + path, {
    ...options,
    credentials: "include",
    headers: {
      ...(options.body ? { "Content-Type": "application/json" } : {}),
      ...(unsafe ? { "X-CSRF-Token": csrf() } : {}),
      ...options.headers,
    },
  });
  const text = await res.text();
  const data = (text ? JSON.parse(text) : null) as (T & Failure) | null;
  if (!res.ok) throw new ApiError(data?.error ?? res.statusText, res.status, data?.retry);
  return data as T;
}

const post = <T>(path: string, body?: unknown) =>
  call<T>(path, { method: "POST", body: body === undefined ? undefined : JSON.stringify(body) });

export const api = {
  me: (): Promise<Me> => call("/api/me"),
  login: (username: string, password: string, remember: boolean): Promise<{ sets: Sets }> =>
    post("/api/login", { username, password, remember }),
  register: (
    code: string,
    username: string,
    password: string,
    remember: boolean,
  ): Promise<{ sets: Sets }> =>
    // No code posts to the codeless route, which only a server with
    // registration `open` accepts
    post(code ? `/api/register/${encodeURIComponent(code)}` : "/api/register", {
      username,
      password,
      remember,
    }),
  /** The one endpoint readable before sign-in */
  health: (): Promise<{ registration?: string; tiles?: boolean }> =>
    call("/api/health"),
  logout: () => post<void>("/api/logout"),
  password: (oldPassword: string, newPassword: string) =>
    post<void>("/api/password", { old: oldPassword, new: newPassword }),

  sets: (): Promise<Sets> => call("/api/sets"),
  /** Pinned stops by feed id: the catalog is rebuilt whenever the city's feed
   * changes, so a stored index quietly becomes a different stop. */
  pins: (): Promise<{ pins: string[] }> => call("/api/pins"),
  setPins: (pins: string[]): Promise<{ pins: string[] }> => post("/api/pins", { pins }),
  places: (): Promise<{ places: Place[] }> => call("/api/places"),
  /** The whole list, every time: the name is the identity server-side, so a
   * rename is the old one dropped and the new one saved in one write */
  setPlaces: (places: Place[]): Promise<{ places: Place[] }> => post("/api/places", { places }),
  createSet: (name: string, routes: string[]): Promise<RouteSet> =>
    post("/api/sets", { name, routes }),
  updateSet: (id: string, name: string, routes: string[]): Promise<RouteSet> =>
    call(`/api/sets/${id}`, { method: "PUT", body: JSON.stringify({ name, routes }) }),
  deleteSet: (id: string) => call<void>(`/api/sets/${id}`, { method: "DELETE" }),
  activateSet: (id: string | null) => post<void>("/api/sets/active", { id }),

  arrivals: (stops: number[]): Promise<Arrivals> =>
    call(`/api/arrivals?stops=${stops.join(",")}`),
  vehicle: (veh: number): Promise<{ t: number; veh: number; stops: Call[] }> =>
    call(`/api/vehicle?veh=${veh}`),
  /** `at` in unix seconds leaves at that time instead of now; a future one has
   * no vehicles to see, so every leg comes back on the timetable */
  plan: (from: [number, number], to: [number, number], at?: number | null): Promise<Plan> =>
    call(
      `/api/plan?from=${from[0]},${from[1]}&to=${to[0]},${to[1]}` +
        (at ? `&at=${Math.round(at)}` : ""),
    ),
  search: (q: string, signal?: AbortSignal): Promise<{ places: Found[] }> =>
    call(`/api/search?q=${encodeURIComponent(q)}`, { signal }),
  traffic: (): Promise<Traffic> => call("/api/traffic"),
};

/** Cached in local storage against the service's ETag: the usual request comes
 * back 304 with no body. */
async function held<T>(path: string, key: string): Promise<T> {
  const stored = localStorage.getItem(key);
  const had = stored ? (JSON.parse(stored) as { tag: string; data: T }) : null;
  const res = await fetch(BASE + path, {
    credentials: "include",
    headers: had ? { "If-None-Match": had.tag } : {},
  });
  if (res.status === 304 && had) return had.data;
  if (!res.ok) throw new ApiError(`${path} ${res.status}`, res.status);
  const data = (await res.json()) as T;
  const tag = res.headers.get("ETag");
  if (tag) {
    try {
      localStorage.setItem(key, JSON.stringify({ tag, data }));
    } catch {
      // A full quota only costs a refetch
    }
  }
  return data;
}

export const catalog = () => held<Catalog>("/api/catalog", "commuterlviv.catalog");

/** Half a megabyte, so fetched only once something draws a route line */
export const shapes = () => held<Shapes>("/api/shapes", "commuterlviv.shapes");

/** Which stretch of street each traffic number belongs to: a quarter of a
 * megabyte that never changes, against numbers that change every minute */
export const streets = () => held<Streets>("/api/traffic/streets", "commuterlviv.streets");
