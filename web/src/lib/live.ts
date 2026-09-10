import { BASE } from "./api";
import type { Arrival } from "./types";
import { decode, DELTA, SNAPSHOT } from "./wire";

/** How long a vehicle takes to slide from where it was drawn to where the
 * server says it is. Positions arrive every five seconds; easing over a little
 * over a second reads as movement without lagging visibly behind the truth. */
const EASE = 1200;

/** The one text frame the socket carries that says anything. Everything else
 * on this socket is binary, and `pong` carries nothing worth reading. */
type ArrivalsMessage = { type: string; t: number; stops: Record<string, Arrival[]> };

type Vehicle = {
  route: number;
  flags: number;
  lat0: number;
  lon0: number;
  lat1: number;
  lon1: number;
  h0: number;
  h1: number;
  t0: number;
};

export type Connection = "connecting" | "live" | "offline";

/** Everything arriving over the socket, and the current position of every
 * vehicle on it.
 *
 * Positions live here rather than in React state on purpose: four hundred
 * vehicles moving sixty times a second is a canvas redraw, not a re-render.
 * React subscribes only to the things that change rarely - the connection, the
 * arrivals, the vehicle count.
 */
export class Live {
  readonly vehicles = new Map<number, Vehicle>();
  arrivals: Record<string, Arrival[]> = {};
  arrivalsAt = 0;
  connection: Connection = "connecting";
  frameAt = 0;

  private ws: WebSocket | null = null;
  private routes: number[] = [];
  private stops: number[] = [];
  private backoff = 500;
  private timer: ReturnType<typeof setTimeout> | undefined;
  private closed = false;
  private listeners = new Set<() => void>();
  private snapshot = { connection: "connecting" as Connection, arrivalsAt: 0, count: 0 };

  subscribe = (fn: () => void) => {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  };

  /** A stable object per meaningful change, so `useSyncExternalStore` does not
   * tear and does not re-render on every position frame. */
  getSnapshot = () => this.snapshot;

  private changed() {
    this.snapshot = {
      connection: this.connection,
      arrivalsAt: this.arrivalsAt,
      count: this.vehicles.size,
    };
    for (const fn of this.listeners) fn();
  }

  open() {
    this.closed = false;
    this.connect();
  }

  close() {
    this.closed = true;
    clearTimeout(this.timer);
    this.ws?.close();
    this.ws = null;
  }

  setRoutes(routes: number[]) {
    this.routes = routes;
    this.vehicles.clear();
    this.send({ type: "routes", routes });
    this.changed();
  }

  setStops(stops: number[]) {
    this.stops = stops;
    this.send({ type: "stops", stops });
  }

  private send(msg: unknown) {
    if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(msg));
  }

  private connect() {
    const url = new URL(BASE + "/ws", location.href);
    url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
    const ws = new WebSocket(url);
    ws.binaryType = "arraybuffer";
    this.ws = ws;

    ws.onopen = () => {
      this.backoff = 500;
      this.connection = "live";
      this.send({ type: "routes", routes: this.routes });
      if (this.stops.length) this.send({ type: "stops", stops: this.stops });
      this.changed();
    };
    ws.onmessage = (e) => {
      if (typeof e.data === "string") this.text(e.data);
      else this.frame(e.data as ArrayBuffer);
    };
    ws.onclose = () => {
      if (this.ws !== ws) return;
      this.ws = null;
      this.connection = this.closed ? "offline" : "connecting";
      this.changed();
      if (!this.closed) {
        this.timer = setTimeout(() => this.connect(), this.backoff);
        this.backoff = Math.min(this.backoff * 2, 15000);
      }
    };
    ws.onerror = () => ws.close();
  }

  private text(raw: string) {
    let msg: Partial<ArrivalsMessage>;
    try {
      msg = JSON.parse(raw) as Partial<ArrivalsMessage>;
    } catch {
      return;
    }
    if (msg.type === "arrivals" && msg.stops !== undefined && msg.t !== undefined) {
      this.arrivals = msg.stops;
      this.arrivalsAt = msg.t;
      this.changed();
    }
  }

  private frame(buf: ArrayBuffer) {
    const f = decode(buf);
    const now = performance.now();
    if (f.kind === SNAPSHOT) this.vehicles.clear();
    for (let i = 0; i < f.n; i++) {
      const id = f.ids[i]!;
      const lat = f.lats[i]!;
      const lon = f.lons[i]!;
      const h = f.headings[i]!;
      const had = this.vehicles.get(id);
      if (had) {
        const [lat0, lon0, h0] = sample(had, now);
        had.lat0 = lat0;
        had.lon0 = lon0;
        had.h0 = h0;
        had.lat1 = lat;
        had.lon1 = lon;
        had.h1 = h;
        had.t0 = now;
        had.route = f.routes[i]!;
        had.flags = f.flags[i]!;
      } else {
        this.vehicles.set(id, {
          route: f.routes[i]!,
          flags: f.flags[i]!,
          lat0: lat,
          lon0: lon,
          lat1: lat,
          lon1: lon,
          h0: h,
          h1: h,
          t0: now,
        });
      }
    }
    if (f.kind === DELTA) for (const id of f.gone) this.vehicles.delete(id);
    this.frameAt = now;
    if (f.kind === SNAPSHOT || f.gone.length) this.changed();
  }
}

/** Where a vehicle is right now, between the last two things the server said.
 * Heading takes the short way round, so a bus turning past north does not spin
 * three hundred degrees the wrong way. */
export function sample(v: Vehicle, now: number): [number, number, number] {
  const k = Math.min(1, (now - v.t0) / EASE);
  const e = k * (2 - k); // ease-out: fastest on arrival, settling into place
  const dh = ((v.h1 - v.h0 + 540) % 360) - 180;
  return [v.lat0 + (v.lat1 - v.lat0) * e, v.lon0 + (v.lon1 - v.lon0) * e, v.h0 + dh * e];
}

export type { Vehicle };
