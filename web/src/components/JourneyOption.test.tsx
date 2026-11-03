import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, test } from "vitest";
import { t } from "../lib/i18n";
import type { Catalog, Journey } from "../lib/types";
import { JourneyOption } from "./JourneyOption";

const MINUTE_S = 60;
const AT = 8 * 60 * MINUTE_S;

const CATALOG: Catalog = {
  routes: [{ id: "r8", short: "8", long: "Eight", type: "tram" }],
  stops: ["Home stop", "Work stop"].map((name, i) => ({
    id: `s${i}`,
    name,
    code: `${i}`,
    lat: 49.84,
    lon: 24.03,
    routes: [0],
  })),
};

/** A stretch along any leg, so the journey can be followed */
const PTS: [number, number][] = [
  [49.84, 24.03],
  [49.841, 24.031],
];

/** Walk to a stop, a ride no vehicle has been seen on, a walk to the door; caught
 *  only by hurrying, with a backup */
const JOURNEY: Journey = {
  dep: AT,
  arr: AT + 29 * MINUTE_S,
  rides: 1,
  live: false,
  confidence: "quiet",
  backup: 2,
  hurry: true,
  legs: [
    { kind: "walk", dep: AT, arr: AT + 5 * MINUTE_S, a: -1, b: 0, pts: PTS },
    {
      kind: "ride",
      dep: AT + 6 * MINUTE_S,
      arr: AT + 25 * MINUTE_S,
      a: 0,
      b: 1,
      route: 0,
      confidence: "quiet",
      pts: PTS,
    },
    { kind: "walk", dep: AT + 25 * MINUTE_S, arr: AT + 29 * MINUTE_S, a: 1, b: -1, pts: PTS },
  ],
};

/** The info glyph an explain chip carried */
const INFO_GLYPH = "M12 11v5";

const card = (shown: boolean, journey = JOURNEY) =>
  renderToStaticMarkup(
    <JourneyOption
      journey={journey}
      shown={shown}
      onShow={() => {}}
      onFollow={() => {}}
      onWay={async () => {}}
      prefer="fastest"
      place={() => 1}
      catalog={CATALOG}
      onStop={() => {}}
      onLine={() => {}}
    />,
  );

const buttons = (html: string) => html.match(/<button[^>]*>/g) ?? [];

/** The buttons titled so, matched as the markup escapes the title */
const titled = (all: string[], title: string) => {
  const attr = renderToStaticMarkup(<b title={title} />).match(/title="[^"]*"/)![0];
  return all.filter((b) => b.includes(attr));
};

describe("JourneyOption", () => {
  test("is one button while unpicked, which still names its hurry, note and backups", () => {
    const html = card(false);

    expect(buttons(html)).toEqual([expect.stringContaining('aria-expanded="false"')]);
    expect(html).toContain(t.hurry);
    expect(html).toContain(t.quietPart);
    expect(html).toContain(t.backupCount(2));
    expect(html).not.toContain(t.hurryHint);
    expect(html).not.toContain("Work stop");
  });

  test("once picked, says its hint and notes in place, with no info chip", () => {
    const html = card(true);

    expect(html).toContain(t.hurryHint);
    expect(html).toContain(t.quietWhy);
    expect(html).toContain(t.toDoor);
    expect(html).not.toContain(INFO_GLYPH);
  });

  test("once picked, makes every stop, the line, the backups and following their own button", () => {
    const html = card(true);
    const all = buttons(html);

    expect(all[0]).toContain('aria-expanded="true"');
    expect(titled(all, t.showLine)).toHaveLength(1);
    expect(titled(all, t.backupHint)).toHaveLength(1);
    expect(titled(all, t.followHint)).toHaveLength(1);
    // The summary, the two stops, the line, the backups and following
    expect(all).toHaveLength(6);
    expect(html).toContain("Work stop");
    expect(html).toContain("Home stop");
  });

  test("tells the minute waited at the stop apart from the 19 ridden, closed and open", () => {
    const closed = card(false);
    const open = card(true);

    expect(closed).toContain(`title="${t.waitLeg(1)}"`);
    expect(closed).toContain(`title="${t.rideLeg(19)}"`);
    expect(open).toContain(`>${t.wait}<`);
    expect(open).toContain(t.minutes(1));
    expect(open).toContain(t.rideLeg(19));
  });

  test("says no wait for a ride boarded as the walk reaches the stop", () => {
    const ride = { ...JOURNEY.legs[1]!, dep: JOURNEY.legs[0]!.arr };
    const html = card(true, { ...JOURNEY, legs: [JOURNEY.legs[0]!, ride, JOURNEY.legs[2]!] });

    expect(html).not.toContain(t.waitLeg(1));
    expect(html).not.toContain(`>${t.wait}<`);
  });
});
