import { describe, expect, test } from "vitest";
import {
  Follower,
  GRACE_S,
  Watch,
  along,
  followable,
  judge,
  margin,
  needKmh,
  plannedKmh,
  type Due,
  type Progress,
  type Reach,
  type Seen,
  type Stage,
} from "./follow";
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

  test("a journey begun on board starts riding its vehicle, then walks the rest", () => {
    const j = journey();
    const trip = new Trip({ ...j, aboard: true, legs: j.legs.slice(1) });
    let p = trip.fix(at(0, 200), [vehicle(PLANNED, 0)]);
    expect(p.stage).toEqual({ kind: "ride", leg: 0, veh: PLANNED });
    trip.east(0, 8, 250, (x) => [vehicle(PLANNED, Math.min(x, 2000))]);
    p = trip.east(2000, 0, 10);
    expect(p.stage).toEqual({ kind: "walk", leg: 1 });
  });

  test("a journey not begun on board waits for its first ride", () => {
    const j = journey();
    const trip = new Trip({ ...j, legs: j.legs.slice(1) });
    expect(trip.fix(at(0, 200)).stage.kind).toBe("wait");
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

/** The second ride's route and vehicle, and when it is timetabled to leave */
const NEXT_ROUTE = 9;
const NEXT = 52;
const NEXT_DEP = 1000;
/** Metres a second: walking, and hurrying at twice that */
const MPS = 1;
const HURRY_MPS = 2 * MPS;

/** The journey above, but from the end of the ride 200 m on north to a stop
 * on route 9, 2 km east on it and 200 m back south to the door */
const changing = (): Journey => {
  const j = journey();
  return {
    ...j,
    rides: 2,
    legs: [
      ...j.legs.slice(0, 2),
      { kind: "walk", dep: 0, arr: 0, a: 2, b: 4, pts: [at(2000, 200), at(2000, 400)] },
      {
        kind: "ride",
        dep: NEXT_DEP,
        arr: 0,
        a: 4,
        b: 5,
        route: NEXT_ROUTE,
        veh: NEXT,
        pts: [at(2000, 400), at(4000, 400)],
      },
      { kind: "walk", dep: 0, arr: 0, a: 5, b: -1, pts: [at(4000, 400), at(4000, 200)] },
    ],
  };
};

/** The predictions: each stop's vehicle and when it gets there */
const predicted =
  (...says: [stop: number, veh: number, t: number][]): Due =>
  (stop, veh) =>
    says.find(([s, v]) => s === stop && v === veh)?.[2];

const riding: Stage = { kind: "ride", leg: 1, veh: PLANNED };

/** Reach `late` seconds after the vehicle leaves at the usual pace, and
 * `hurriedLate` at the hurrying one */
const reach = (late: number, hurriedLate = late, live = true): Reach => ({
  leg: 3,
  dep: NEXT_DEP,
  live,
  from: NEXT_DEP - 120,
  walk: 300,
  usual: NEXT_DEP + late,
  hurried: NEXT_DEP + hurriedLate,
});

describe("the next connection", () => {
  test("walking to the stop is timed from the metres left", () => {
    const trip = new Trip(changing());
    trip.fix(at(0, 50));

    const r = trip.follower.reach(predicted(), 0, MPS, HURRY_MPS)!;

    expect(r.leg).toBe(1);
    expect(r.usual).toBeCloseTo(150);
    expect(r.hurried).toBeCloseTo(75);
    expect(r.live).toBe(false);
  });

  test("on a ride the change is timed from when the vehicle ridden gets off", () => {
    const off = 700;
    const follower = new Follower(changing(), catalog, riding);

    const r = follower.reach(predicted([2, PLANNED, off], [4, NEXT, 950]), 0, MPS, HURRY_MPS)!;

    expect(r).toMatchObject({ leg: 3, dep: 950, live: true });
    expect(r.usual).toBeCloseTo(off + 200);
    expect(r.hurried).toBeCloseTo(off + 100);
  });

  test("an untracked next ride goes by its timetable", () => {
    const follower = new Follower(changing(), catalog, riding);

    const r = follower.reach(predicted([2, PLANNED, 0]), 0, MPS, HURRY_MPS)!;

    expect(r.dep).toBe(NEXT_DEP);
    expect(r.live).toBe(false);
  });

  test("nothing is said while waiting, or riding a vehicle not known", () => {
    const due = predicted([2, PLANNED, 0]);

    for (const stage of [
      { kind: "wait", leg: 1 },
      { kind: "ride", leg: 1, veh: null },
      { kind: "ride", leg: 3, veh: NEXT },
    ] as Stage[]) {
      expect(new Follower(changing(), catalog, stage).reach(due, 0, MPS, HURRY_MPS)).toBeNull();
    }
  });

  test("a resumed journey starts where it was", () => {
    expect(new Follower(changing(), catalog, riding).progress.stage).toEqual(riding);
  });

  test("on time, by hurrying, by the grace of a tracked vehicle, or missed", () => {
    expect(judge(reach(0))).toBe("ok");
    expect(judge(reach(1, 0))).toBe("hurry");
    expect(judge(reach(30, 0))).toBe("hurry");
    expect(judge(reach(30, GRACE_S))).toBe("hurry");
    expect(judge(reach(30, GRACE_S, false))).toBe("missed");
    expect(judge(reach(30, GRACE_S + 1))).toBe("missed");
  });

  test("a worse word waits until it has held, a better one does not", () => {
    const watch = new Watch();
    // Far enough ahead for its prediction to still be jumpy
    const now = NEXT_DEP - 600;

    expect(watch.update(reach(30), riding, now).kind).toBe("ok");
    expect(watch.update(reach(30), riding, now + 5).kind).toBe("ok");
    expect(watch.update(reach(30), riding, now + 10)).toEqual({
      kind: "missed",
      leg: 3,
      dep: NEXT_DEP,
      riding: true,
      kmh: null,
    });
    expect(watch.update(reach(0), riding, now + 11).kind).toBe("ok");
  });

  test("one jumpy prediction is not news", () => {
    const watch = new Watch();
    const now = NEXT_DEP - 600;

    watch.update(reach(30), riding, now);
    watch.update(reach(0), riding, now + 5);

    expect(watch.update(reach(30), riding, now + 10).kind).toBe("ok");
  });

  test("close to leaving a worse word is said at once", () => {
    expect(new Watch().update(reach(30), riding, NEXT_DEP - 60).kind).toBe("missed");
  });

  test("hurrying is urged on foot, and only warned of on a ride", () => {
    const now = NEXT_DEP - 60;
    const walking: Stage = { kind: "walk", leg: 2 };

    expect(new Watch().update(reach(30, 0), riding, now)).toMatchObject({ riding: true });
    expect(new Watch().update(reach(30, 0), walking, now)).toMatchObject({ riding: false });
  });

  test("a word about one ride is not said of the next", () => {
    const watch = new Watch();
    const now = NEXT_DEP - 60;
    const hurry = watch.update(reach(30, 0), { kind: "walk", leg: 2 }, now);
    // A change further on, far enough ahead for its prediction to be jumpy
    const later = NEXT_DEP + 600;
    const after: Reach = {
      leg: 5,
      dep: later,
      live: true,
      from: now,
      walk: 300,
      usual: later + 30,
      hurried: later + 30,
    };

    expect(hurry.kind).toBe("hurry");
    expect(watch.update(after, { kind: "ride", leg: 3, veh: NEXT }, now + 1).kind).toBe("ok");
  });

  test("waiting at the stop of a missed ride still has it missed", () => {
    const watch = new Watch();
    watch.update(reach(30), { kind: "walk", leg: 2 }, NEXT_DEP - 60);

    expect(watch.update(null, { kind: "wait", leg: 3 }, NEXT_DEP).kind).toBe("missed");
    expect(watch.update(null, { kind: "ride", leg: 3, veh: NEXT }, NEXT_DEP).kind).toBe("ok");
  });
});

/** Metres north of 49.84 N in degrees of latitude, as `along` measures them */
const north = (m: number) => m / ((6_371_000 * Math.PI) / 180);

describe("the pace hurrying needs", () => {
  test("keeps half a change's slack, more the further ahead the ride leaves", () => {
    expect(margin(0)).toBe(30);
    expect(margin(300)).toBeCloseTo(56.25);
    expect(margin(9999)).toBe(150);
  });

  test("walks there with the margin to spare, rounded up to a step", () => {
    // 300 m in 300 - 56.25 s is 4.43 km/h
    expect(needKmh(300, 0, 300)).toBe(4.5);
  });

  test("is timed from when the ride was forecast, not from setting off", () => {
    // off a ride at 600 for a ride leaving at 900: forecast 900 s ahead, not 300
    expect(needKmh(300, 600, 900, 0)).toBeGreaterThan(needKmh(300, 600, 900)!);
  });

  test("drops the margin rather than ask for more than a run", () => {
    // with the margin 66 s for 300 m, 16.4 km/h; right at the ride 10.8
    expect(needKmh(300, 0, 100)).toBe(11);
  });

  test("is nothing once no time is left, or with nothing to walk", () => {
    expect(needKmh(300, 100, 100)).toBeNull();
    expect(needKmh(0, 0, 300)).toBeNull();
  });

  test("of a planned option is read off its first walk", () => {
    const pts: [number, number][] = [
      [49.84, 24.03],
      [49.84 + north(300), 24.03],
    ];
    expect(along(pts)).toBeCloseTo(300);
    const option = {
      legs: [
        { kind: "walk", dep: 0, arr: 300, a: -1, b: 0, pts },
        { kind: "ride", dep: 300, arr: 600, a: 0, b: 1 },
      ],
    } as unknown as Journey;
    expect(plannedKmh(option)).toBe(4.5);
  });

  test("is said with a hurry, and not with a miss", () => {
    const hurry = new Watch().update(reach(30, 0), { kind: "walk", leg: 2 }, NEXT_DEP - 120);
    const missed = new Watch().update(reach(30), { kind: "walk", leg: 2 }, NEXT_DEP - 60);

    expect(hurry).toMatchObject({ kind: "hurry", kmh: needKmh(300, NEXT_DEP - 120, NEXT_DEP) });
    expect(missed).toMatchObject({ kind: "missed", kmh: null });
  });
});
