import type { Arrivals, Catalog, Me, RouteSet, Sets, Status } from "./types";

/** Same origin by default: in development Vite proxies `/api` and `/ws` to the
 * service, so the session cookie is a first-party cookie in both settings. */
export const BASE = import.meta.env.VITE_API_URL ?? "";

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

async function call(path: string, options: RequestInit = {}): Promise<any> {
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
  const data = text ? JSON.parse(text) : null;
  if (!res.ok) throw new ApiError(data?.error ?? res.statusText, res.status, data?.retry);
  return data;
}

const post = (path: string, body?: unknown) =>
  call(path, { method: "POST", body: body === undefined ? undefined : JSON.stringify(body) });

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
  /** `open`, `code` or `closed` - asked before anyone is signed in, so it is on
   * the one public endpoint */
  registration: async (): Promise<string> =>
    ((await call("/api/health")) as { registration?: string }).registration ?? "code",
  logout: () => post("/api/logout"),
  password: (oldPassword: string, newPassword: string) =>
    post("/api/password", { old: oldPassword, new: newPassword }),

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
  deleteSet: (id: string) => call(`/api/sets/${id}`, { method: "DELETE" }),
  activateSet: (id: string | null) => post("/api/sets/active", { id }),

  arrivals: (stops: number[]): Promise<Arrivals> =>
    call(`/api/arrivals?stops=${stops.join(",")}`),
  status: (): Promise<Status> => call("/api/status"),
};

const CATALOG_KEY = "commuterlviv.catalog";

/** The catalog is a megabyte of names that never change while the service is
 * up, so it is kept in local storage against the tag the service sends and the
 * usual request is a 304 with no body. */
export async function catalog(): Promise<Catalog> {
  const cached = localStorage.getItem(CATALOG_KEY);
  const held = cached ? (JSON.parse(cached) as { tag: string; data: Catalog }) : null;
  const res = await fetch(BASE + "/api/catalog", {
    credentials: "include",
    headers: held ? { "If-None-Match": held.tag } : {},
  });
  if (res.status === 304 && held) return held.data;
  if (!res.ok) throw new ApiError(`catalog ${res.status}`, res.status);
  const data = (await res.json()) as Catalog;
  const tag = res.headers.get("ETag");
  if (tag) {
    try {
      localStorage.setItem(CATALOG_KEY, JSON.stringify({ tag, data }));
    } catch {
      // A full quota is not a reason to fail the load - it only costs a refetch
    }
  }
  return data;
}
