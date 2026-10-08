import { describe, expect, test } from "vitest";
import { Follower, followable, type Progress, type Seen } from "./follow";
import type { Catalog, Journey } from "./types";

const LAT0 = 49.84;
const LON0 = 24.03;
const ROUTE = 7;
const PLANNED = 41;
const FIX_EVERY_MS = 2000;
const M_PER_DEGREE = (6371000 * Math.PI) / 180;

/** A point `east` and `north` metres from the journey's start */
const at = (east: number, north: number): [number, number] => [
  LAT0 + north / M_PER_DEGREE,
  LON0 + east / (M_PER_DEGREE * Math.cos((LAT0 * Math.PI) / 180)),
];

/** From the door 200 m north to a stop, 2 km east on route 7 calling at
 * `stops` on the way, then 200 m south to the door */
const journey = ({ veh = PLANNED, stops }: { veh?: number | null; stops?: number[] } = {}): Journey => ({
  dep: 0,
  arr: 0,
  rides: 1,
  live: veh !== null,
  confidence: "live",
  backup: 0,
  legs: [
    { kind: "walk", dep: 0, arr: 0, a: -1, b: 1, pts: [at(0, 0), at(0, 200)] },
    {
      kind: "ride",
      dep: 0,
      arr: 0,
      a: 1,
      b: 2,
      route: ROUTE,
      veh,
      stops,
      pts: [at(0, 200), at(1000, 200), at(2000, 200)],
    },
    { kind: "walk", dep: 0, arr: 0, a: 2, b: -1, pts: [at(2000, 200), at(2000, 0)] },
  ],
});

/** Stop 1 is boarded at, 2 got off at, and 3 lies between them, 1200 m on */
const catalog: Catalog = {
  routes: [],
  stops: [at(0, 0), at(0, 200), at(2000, 200), at(1200, 200)].map(([lat, lon], i) => ({
    id: `s${i}`,
    name: `${i}`,
    code: `${i}`,
    lat,
    lon,
    routes: [],
  })),
};

const none = (_: number): Seen[] => [];

/** Drives a `Follower` one fix at a time, every `FIX_EVERY_MS` */
class Trip {
  readonly follower: Follower;
  t = 0;

  constructor(j: Journey) {
    this.follower = new Follower(j, catalog);
  }

  fix([lat, lon]: [number, number], seen: Seen[] = [], accuracy = 10): Progress {
    this.t += FIX_EVERY_MS;
    return this.follower.update({ lat, lon, accuracy, t: this.t }, seen);
  }

  /** Fixes at `from` moving `mps` east along the ride, `n` of them, with
   * vehicles placed by `seen` at each */
  east(from: number, mps: number, n: number, seen: (east: number) => Seen[] = none): Progress {
    let p: Progress | undefined;
    for (let k = 0; k < n; k++) {
      const x = from + (mps * k * FIX_EVERY_MS) / 1000;
      p = this.fix(at(x, 200), seen(x));
    }
    return p!;
  }
}

function vehicle(id: number, east: number, onRoute = ROUTE): Seen {
  const [lat, lon] = at(east, 200);
  return { id, route: onRoute, lat, lon };
}

/** Walks the first leg to the stop */
function atStop(j: Journey): Trip {
  const trip = new Trip(j);
  for (let n = 0; n <= 200; n += 25) trip.fix(at(0, n));
  return trip;
}

describe("follow", () => {
  test("walking to the stop waits there for the ride", () => {
    const trip = atStop(journey());
    const p = trip.fix(at(0, 200));
    expect(p.stage.kind).toBe("wait");
    expect(p.stage).toHaveProperty("leg", 1);
  });

  test("standing beside a tram at the stop is not boarding it", () => {
    const trip = atStop(journey());
    const p = trip.east(0, 0, 30, () => [vehicle(PLANNED, 5)]);
    expect(p.stage.kind).toBe("wait");
  });

  test("riding away with the tram boards it, within a few fixes", () => {
    const trip = atStop(journey());
    trip.east(0, 0, 5, () => [vehicle(PLANNED, 0)]);
    const p = trip.east(0, 8, 8, (x) => [vehicle(PLANNED, x - 20)]);
    expect(p.stage.kind).toBe("ride");
    expect(p.stage).toHaveProperty("veh", PLANNED);
  });

  test("another vehicle of the route is picked when it is the one riding", () => {
    const trip = atStop(journey());
    const p = trip.east(0, 8, 10, (x) => [vehicle(PLANNED, 900), vehicle(12, x + 15)]);
    expect(p.stage.kind).toBe("ride");
    expect(p.stage).toHaveProperty("veh", 12);
  });

  test("the planned tram left standing at the stop is not the one ridden", () => {
    const trip = atStop(journey());
    const p = trip.east(0, 8, 10, (x) => [vehicle(PLANNED, 0), vehicle(12, x + 15)]);
    expect(p.stage.kind).toBe("ride");
    expect(p.stage).toHaveProperty("veh", 12);
  });

  test("a tram drawn standing as it leaves is matched once it is drawn moving", () => {
    const trip = atStop(journey());
    // The map keeps a vehicle where it stood until a fix shows it moving,
    // which reaches the server some 10-20 s after it pulled away, and then
    // draws it a little behind
    const late = (x: number) => [vehicle(PLANNED, x < 160 ? 0 : x - 60)];
    let p = trip.east(0, 8, 10, late);
    expect(p.stage.kind).toBe("ride");
    expect(p.stage).toHaveProperty("veh", null);
    p = trip.east(160, 8, 10, late);
    expect(p.stage).toHaveProperty("veh", PLANNED);
  });

  test("the planned vehicle wins over another also keeping pace", () => {
    const trip = atStop(journey());
    const p = trip.east(0, 8, 10, (x) => [vehicle(12, x + 5), vehicle(PLANNED, x + 40)]);
    expect(p.stage).toHaveProperty("veh", PLANNED);
  });

  test("a vehicle of another route keeping pace is not the ride", () => {
    const trip = atStop(journey());
    const p = trip.east(0, 8, 10, (x) => [vehicle(5, x, 99)]);
    expect(p.stage.kind).toBe("ride");
    expect(p.stage).toHaveProperty("veh", null);
  });

  test("walking along the line is not riding it", () => {
    const trip = atStop(journey());
    const p = trip.east(0, 1.6, 25, (x) => [vehicle(PLANNED, x)]);
    expect(p.stage.kind).toBe("wait");
  });

  test("one jump of the GPS ahead is not a ride", () => {
    const trip = atStop(journey());
    trip.east(0, 0, 5);
    const p = trip.fix(at(160, 200));
    expect(p.stage.kind).toBe("wait");
  });

  test("a vague fix changes nothing", () => {
    const trip = atStop(journey());
    trip.east(0, 0, 3);
    const p = trip.east(0, 8, 10, (x) => [vehicle(PLANNED, x)]);
    const still = trip.fix(at(1990, 200), [], 200);
    expect(still.stage.kind).toBe(p.stage.kind);
    expect(still.left).toBe(p.left);
  });

  test("a fix older than the last changes nothing", () => {
    const trip = atStop(journey());
    const p = trip.east(0, 8, 10, (x) => [vehicle(PLANNED, x)]);
    trip.t -= 3 * FIX_EVERY_MS;
    const late = trip.fix(at(0, 200));
    expect(late.stage.kind).toBe(p.stage.kind);
    expect(late.left).toBe(p.left);
  });

  test("a ride on a timetable vehicle boards on movement alone", () => {
    const trip = atStop(journey({ veh: null }));
    const p = trip.east(0, 8, 10);
    expect(p.stage.kind).toBe("ride");
    expect(p.stage).toHaveProperty("veh", null);
  });

  test("a ridden vehicle that drops out is found again", () => {
    const trip = atStop(journey());
    trip.east(0, 8, 10, (x) => [vehicle(PLANNED, x)]);
    const p = trip.east(160, 8, 12, (x) => [vehicle(12, x + 10)]);
    expect(p.stage.kind).toBe("ride");
    expect(p.stage).toHaveProperty("veh", 12);
  });

  test("a ridden vehicle whose id comes back on another route is let go", () => {
    // A second ride on route 99, so the follower watches that route too
    const j = journey();
    const transfer: Journey = {
      dep: 0,
      arr: 0,
      rides: 2,
      live: true,
      confidence: "live",
      backup: 0,
      legs: [
        ...j.legs.slice(0, 2),
        { kind: "walk", dep: 0, arr: 0, a: 2, b: 3, pts: [at(2000, 200)] },
        { kind: "ride", dep: 0, arr: 0, a: 3, b: 4, route: 99, pts: [at(2000, 200), at(2000, 2000)] },
        { kind: "walk", dep: 0, arr: 0, a: 4, b: -1, pts: [at(2000, 2000)] },
      ],
    };
    const trip = atStop(transfer);
    trip.east(0, 8, 10, (x) => [vehicle(PLANNED, x)]);
    const p = trip.east(160, 8, 6, (x) => [vehicle(PLANNED, x, 99)]);
    expect(p.stage.kind).toBe("ride");
    expect(p.stage).toHaveProperty("veh", null);
  });

  test("getting ready starts at the last stop before the one to get off at", () => {
    const trip = atStop(journey({ stops: [3] }));
    let p = trip.east(0, 8, 70, (x) => [vehicle(PLANNED, x)]);
    expect(p.stage.kind).toBe("ride");
    expect(p.soon).toBe(false);
    p = trip.east(1120, 8, 4, (x) => [vehicle(PLANNED, x)]);
    expect(p.soon).toBe(true);
  });

  test("a ride of one stop is getting ready from boarding", () => {
    const trip = atStop(journey({ stops: [] }));
    const p = trip.east(0, 8, 10, (x) => [vehicle(PLANNED, x)]);
    expect(p.stage.kind).toBe("ride");
    expect(p.soon).toBe(true);
  });

  test("without the stops on the way, getting ready is 400 m out", () => {
    const trip = atStop(journey());
    let p = trip.east(0, 8, 100, (x) => [vehicle(PLANNED, x)]);
    expect(p.stage.kind).toBe("ride");
    expect(p.soon).toBe(false);
    p = trip.east(1600, 8, 3, (x) => [vehicle(PLANNED, x)]);
    expect(p.soon).toBe(true);
  });

  test("getting off at the stop walks the rest, then arrives", () => {
    const trip = atStop(journey());
    trip.east(0, 8, 250, (x) => [vehicle(PLANNED, Math.min(x, 2000))]);
    let p = trip.east(2000, 0, 10);
    expect(p.stage.kind).toBe("walk");
    expect(p.stage).toHaveProperty("leg", 2);
    expect(p.passed).toBe(false);
    for (let n = 200; n >= 0; n -= 25) p = trip.fix(at(2000, n));
    expect(p.stage.kind).toBe("arrived");
  });

  test("staying on past the stop says so", () => {
    const trip = atStop(journey());
    trip.east(0, 8, 245, (x) => [vehicle(PLANNED, x)]);
    const p = trip.east(1960, 8, 30);
    expect(p.stage.kind).toBe("ride");
    expect(p.passed).toBe(true);
  });

  test("a stop dwelt at and then left on the vehicle says so on the walk", () => {
    const trip = atStop(journey());
    trip.east(0, 8, 250);
    trip.east(2000, 0, 10);
    const p = trip.east(2000, 8, 25);
    expect(p.stage.kind).toBe("walk");
    expect(p.passed).toBe(true);
  });

  test("a journey without lines cannot be followed", () => {
    const j = journey();
    expect(followable(j)).toBe(true);
    expect(
      followable({
        dep: 0,
        arr: 0,
        rides: 0,
        live: false,
        confidence: "live",
        backup: 0,
        legs: [{ kind: "walk", dep: 0, arr: 0, a: -1, b: -1 }],
      }),
    ).toBe(false);
  });
});
