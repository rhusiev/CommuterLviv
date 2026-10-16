import { beforeEach, describe, expect, test, vi } from "vitest";
import { Live } from "./live";

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
