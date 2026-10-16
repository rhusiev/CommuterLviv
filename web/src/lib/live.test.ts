import { beforeEach, describe, expect, test, vi } from "vitest";
import { Live, sample, type Vehicle } from "./live";

/** The socket the client opened, to be spoken through */
let socket: FakeSocket;

class FakeSocket {
  static OPEN = 1;
  readyState = FakeSocket.OPEN;
  binaryType = "";
  onopen: (() => void) | null = null;
  onmessage: ((e: { data: unknown }) => void) | null = null;
  onclose: (() => void) | null = null;
  onerror: (() => void) | null = null;

  constructor() {
    socket = this;
  }

  send() {}

  close() {
    this.onclose?.();
  }

  say(msg: object) {
    this.onmessage?.({ data: JSON.stringify(msg) });
  }
}

vi.stubGlobal("WebSocket", FakeSocket);
vi.stubGlobal("location", { href: "http://testserver/" });

describe("the vehicles going quiet", () => {
  let live: Live;

  beforeEach(() => {
    live = new Live(() => {});
    live.open();
  });

  test("is taken from the hello, then from each change the service sends", () => {
    socket.say({ type: "hello", quiet: true });
    expect(live.getSnapshot().quiet).toBe(true);

    socket.say({ type: "quiet", quiet: false });
    expect(live.getSnapshot().quiet).toBe(false);
  });

  test("is not known once the socket is down", () => {
    socket.say({ type: "hello", quiet: true });
    live.close();

    expect(live.getSnapshot().quiet).toBe(false);
  });
});

/** Long past any slide */
const LATER_MS = 60_000;

const moving = (t0: number): Vehicle => ({
  route: 0,
  flags: 0,
  lat0: 49.8,
  lon0: 24.0,
  lat1: 49.9,
  lon1: 24.1,
  h0: 0,
  h1: 0,
  t0,
});

describe("sample", () => {
  test("starts a vehicle just reported where it was, on the clock reports are stamped with", () => {
    const [lat, lon] = sample(moving(performance.now()));
    expect(lat).toBeCloseTo(49.8, 2);
    expect(lon).toBeCloseTo(24.0, 2);
  });

  test("ends the slide at the vehicle's new position", () => {
    const [lat, lon] = sample(moving(0), LATER_MS);
    expect([lat, lon]).toEqual([49.9, 24.1]);
  });
});
