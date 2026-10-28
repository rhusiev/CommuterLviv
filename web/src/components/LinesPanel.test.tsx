import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, test } from "vitest";
import { t } from "../lib/i18n";
import type { Catalog } from "../lib/types";
import { LineView, LinesBrowse } from "./LinesPanel";

const CATALOG: Catalog = {
  routes: [
    { id: "r1", short: "1", long: "Вокзал - Сихів", type: "bus" },
    { id: "r2", short: "2", long: "Левандівка - Личаків", type: "tram" },
  ],
  stops: [
    { id: "s0", name: "Вокзал", code: "1", lat: 49.84, lon: 24.0, routes: [0] },
    { id: "s1", name: "Площа Ринок", code: "2", lat: 49.84, lon: 24.03, routes: [0] },
    { id: "s2", name: "Сихів", code: "3", lat: 49.8, lon: 24.06, routes: [0] },
  ],
};

const SOON_S = 300;

const browse = (over: Partial<Parameters<typeof LinesBrowse>[0]> = {}) =>
  renderToStaticMarkup(
    <LinesBrowse
      catalog={CATALOG}
      picked={new Set(["r1"])}
      onToggle={() => {}}
      onClear={() => {}}
      onPickAll={() => {}}
      onOpen={() => {}}
      recent={["r2", "gone"]}
      sets={[{ id: "a", name: "Commute", routes: ["r1"], ord: 0 }]}
      active="a"
      onActivate={() => {}}
      onCreate={() => Promise.resolve()}
      onUpdate={() => Promise.resolve()}
      {...over}
    />,
  );

const line = (over: Partial<Parameters<typeof LineView>[0]> = {}) =>
  renderToStaticMarkup(
    <LineView
      catalog={CATALOG}
      route={0}
      ways={[
        { dir: 0, stops: [0, 1, 2] },
        { dir: 1, stops: [2, 1, 0] },
      ]}
      way={0}
      onWay={() => {}}
      arrivals={{ "1": [{ route: 0, veh: 7, t: Date.now() / 1000 + SOON_S }] }}
      watching={false}
      onWatch={() => {}}
      onStop={() => {}}
      onBack={() => {}}
      folded={false}
      onFold={() => {}}
      {...over}
    />,
  );

describe("LinesBrowse", () => {
  test("offers what the map watches, the lines opened lately, then the routes and their filters, in that order", () => {
    const html = browse();
    const at = [t.onMap, t.allRoutes, "Commute", t.recentLines, "Левандівка", t.routes, t.nearLines, t.onlyWatched].map(
      (s) => html.indexOf(s),
    );

    expect(at.every((i) => i >= 0)).toBe(true);
    expect(at).toEqual([...at].sort((a, b) => a - b));
  });

  /** The choice of what the map watches, by its label: whether it is checked */
  const chosen = (html: string, label: string) =>
    html.match(new RegExp(`role="radio" aria-checked="(true|false)"[^>]*>${label}<`))?.[1];

  test("checks the set the map watches, and not every route", () => {
    const html = browse();

    expect(chosen(html, "Commute")).toBe("true");
    expect(chosen(html, t.allRoutes)).toBe("false");
  });

  test("checks every route once each is watched and no set is", () => {
    const html = browse({ picked: new Set(["r1", "r2"]), active: null });

    expect(chosen(html, t.allRoutes)).toBe("true");
    expect(chosen(html, "Commute")).toBe("false");
  });

  test("filters the list with toggles, which are no choice of what the map watches", () => {
    const html = browse();
    const toggle = (label: string) =>
      new RegExp(`<button aria-pressed="false"[^>]*>(?:(?!</button>).)*${label}</button>`).test(html);

    expect(toggle(t.nearLines)).toBe(true);
    expect(toggle(t.onlyWatched)).toBe(true);
    expect(html.match(/role="radio"/g)).toHaveLength(2);
  });

  test("leaves out the lines opened lately once none of them is in the catalog", () => {
    expect(browse({ recent: ["gone"] })).not.toContain(t.recentLines);
  });
});

describe("LineView", () => {
  test("lists the stops of the way shown, towards its last stop", () => {
    const html = line();
    const at = ["Вокзал</span>", "Площа Ринок", "Сихів</span>"].map((s) => html.indexOf(s));

    expect(html).toContain("→ Сихів");
    expect(at.every((i) => i >= 0)).toBe(true);
    expect(at).toEqual([...at].sort((a, b) => a - b));
  });

  test("turns the other way round", () => {
    const html = line({ way: 1 });

    expect(html).toContain("→ Вокзал");
    expect(html.indexOf("Сихів</span>")).toBeLessThan(html.indexOf("Площа Ринок"));
  });

  test("puts the vehicle and the countdown at the stop it is heading for", () => {
    const html = line();
    const row = html.slice(html.indexOf("Площа Ринок") - 300, html.indexOf("Площа Ринок") + 300);

    expect(html.split(t.vehicleHere)).toHaveLength(3); // title and label, once
    expect(row).toContain(t.vehicleHere);
    expect(row).toContain(t.minutes(SOON_S / 60));
  });

  test("folds down to its title, keeping the stops off the map's way", () => {
    const html = line({ folded: true });

    expect(html).toContain("Вокзал - Сихів");
    expect(html).toContain(`title="${t.showStops}"`);
    expect(html).not.toContain("Площа Ринок");
    expect(html).not.toContain(t.watchLine);
  });

  test("says when the shapes hold no stops for the line", () => {
    expect(line({ ways: [{ dir: 0, stops: [] }] })).toContain(t.noLineStops);
  });
});
