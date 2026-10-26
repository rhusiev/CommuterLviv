import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, test } from "vitest";
import { t } from "../lib/i18n";
import type { Catalog } from "../lib/types";
import { MinePanel, type MineSection } from "./MinePanel";

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
      section="stops"
      onSection={() => {}}
      {...over}
    />,
  );

describe("MinePanel", () => {
  test("shows only the list switched to", () => {
    const shown = (section: MineSection) =>
      ["Площа Ринок", "Home", "Commute", "settings"].filter((s) => panel({ section }).includes(s));

    expect(shown("stops")).toEqual(["Площа Ринок"]);
    expect(shown("places")).toEqual(["Home"]);
    expect(shown("sets")).toEqual(["Commute"]);
    expect(shown("account")).toEqual(["settings"]);
  });

  test("offers the switch and the account whichever list is shown", () => {
    const html = panel({ section: "sets" });

    for (const label of [t.mineStops, t.minePlaces, t.sets, "tester"]) expect(html).toContain(label);
  });

  test("lists a pinned stop once, with what is due there", () => {
    const html = panel();

    expect(html.split("Площа Ринок")).toHaveLength(2);
    expect(html).toContain(CATALOG.routes[0]!.long);
  });

  test("says how to fill each list that is empty", () => {
    const empty = { pins: [], places: [], sets: [] };

    expect(panel({ ...empty, section: "stops" })).toContain(t.nothingPinned);
    expect(panel({ ...empty, section: "places" })).toContain(t.nothingSaved);
    expect(panel({ ...empty, section: "sets" })).toContain(t.noSets);
  });
});
