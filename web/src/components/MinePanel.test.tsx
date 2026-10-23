import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, test } from "vitest";
import { t } from "../lib/i18n";
import type { Catalog } from "../lib/types";
import { MinePanel } from "./MinePanel";

const CATALOG: Catalog = {
  routes: [{ id: "r1", short: "1", long: "Вокзал - Сихів", type: "bus" }],
  stops: [{ id: "s1", name: "Площа Ринок", code: "0061", lat: 49.84, lon: 24.03, routes: [0] }],
};

const panel = (over: Partial<Parameters<typeof MinePanel>[0]> = {}) =>
  renderToStaticMarkup(
    <MinePanel
      catalog={CATALOG}
      arrivals={{ "0": [{ route: 0, veh: 3, t: Date.now() / 1000 + 120 }] }}
      pins={[0]}
      onPins={() => {}}
      onStop={() => {}}
      watching={new Set()}
      onToggle={() => {}}
      onRoute={() => {}}
      places={[{ name: "Home", lat: 49.8, lon: 24 }]}
      onPlaces={() => {}}
      onPlace={() => {}}
      sets={[{ id: "a", name: "Commute", routes: ["r1"], ord: 0 }]}
      active="a"
      onActivate={() => {}}
      onDelete={() => Promise.resolve()}
      username="tester"
      account={<p>settings</p>}
      {...over}
    />,
  );

describe("MinePanel", () => {
  test("holds the pinned stops, the places and the sets, with the account last", () => {
    const html = panel();
    const at = [t.pinnedStops, "Площа Ринок", t.places, "Home", t.sets, "Commute", t.account].map(
      (s) => html.indexOf(s),
    );

    expect(at.every((i) => i >= 0)).toBe(true);
    expect(at).toEqual([...at].sort((a, b) => a - b));
  });

  test("lists a pinned stop once, with what is due there", () => {
    const html = panel();

    expect(html.split("Площа Ринок")).toHaveLength(2);
    expect(html).toContain(CATALOG.routes[0]!.long);
  });

  test("keeps the account settings folded until the row is opened", () => {
    expect(panel()).not.toContain("settings");
  });

  test("says how to fill each section that is empty", () => {
    const html = panel({ pins: [], places: [], sets: [] });

    expect(html).toContain(t.nothingPinned);
    expect(html).toContain(t.nothingSaved);
    expect(html).toContain(t.noSets);
  });
});
