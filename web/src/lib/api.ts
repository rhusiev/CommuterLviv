import type { Arrivals, Call, Catalog, Me, Plan, RouteSet, Sets, Shapes } from "./types";

/** Same origin by default: in development Vite proxies `/api` and `/ws` to the
 * service, so the session cookie is a first-party cookie in both settings. */
export const BASE = import.meta.env.VITE_API_URL ?? "";

/** What the service says instead, when it says no. Every handler answers in
 * this shape, so an error body is typed even where the success body is not. */
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

/** The caller names what it expects back. The service is the only source of
 * that shape and TypeScript cannot check it across the wire, so this is an
 * assertion rather than a proof - but it is one assertion, made once, instead
 * of `any` spreading out of every call site. */
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
    // No code posts to the codeless route, which only a server whose
    // registration is `open` accepts
    post(code ? `/api/register/${encodeURIComponent(code)}` : "/api/register", {
      username,
      password,
      remember,
    }),
  /** What a client has to know before anyone is signed in: which registration
   * mode this service is in, and whether it serves its own basemap. Both are on
   * the one public endpoint for that reason. */
  health: (): Promise<{ registration?: string; tiles?: boolean }> =>
    call("/api/health"),
  logout: () => post<void>("/api/logout"),
  password: (oldPassword: string, newPassword: string) =>
    post<void>("/api/password", { old: oldPassword, new: newPassword }),

  sets: (): Promise<Sets> => call("/api/sets"),
  /** Pinned stops, by feed id. Indexes are a property of one catalog and the
   * catalog is rebuilt whenever the city's feed changes, so a stored index
   * quietly becomes a different stop; an id does not. */
  pins: (): Promise<{ pins: string[] }> => call("/api/pins"),
  setPins: (pins: string[]): Promise<{ pins: string[] }> => post("/api/pins", { pins }),
  createSet: (name: string, routes: string[]): Promise<RouteSet> =>
    post("/api/sets", { name, routes }),
  updateSet: (id: string, name: string, routes: string[]): Promise<RouteSet> =>
    call(`/api/sets/${id}`, { method: "PUT", body: JSON.stringify({ name, routes }) }),
  deleteSet: (id: string) => call<void>(`/api/sets/${id}`, { method: "DELETE" }),
  activateSet: (id: string | null) => post<void>("/api/sets/active", { id }),

  arrivals: (stops: number[]): Promise<Arrivals> =>
    call(`/api/arrivals?stops=${stops.join(",")}`),
  /** Where one vehicle is going, and when it gets there: the predictions
   * `arrivals` reads, asked the other way round */
  vehicle: (veh: number): Promise<{ t: number; veh: number; stops: Call[] }> =>
    call(`/api/vehicle?veh=${veh}`),
  /** Door to door, ranked by arrival. Most of a second at the far end, so it
   * is asked once per search and not on every keystroke */
  plan: (from: [number, number], to: [number, number]): Promise<Plan> =>
    call(`/api/plan?from=${from[0]},${from[1]}&to=${to[0]},${to[1]}`),
};

/** A body that never changes while the service is up, kept in local storage
 * against the tag the service sends: the usual request is a 304 with no body. */
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
      // A full quota is not a reason to fail the load - it only costs a refetch
    }
  }
  return data;
}

/** A megabyte of names */
export const catalog = () => held<Catalog>("/api/catalog", "commuterlviv.catalog");

/** Half a megabyte of geometry, asked for only once something wants to draw a
 * route line: the rider who never opens the route view never pays for it. */
export const shapes = () => held<Shapes>("/api/shapes", "commuterlviv.shapes");
