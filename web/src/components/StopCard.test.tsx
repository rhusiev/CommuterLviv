import type { ReactElement, ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, test, vi } from "vitest";
import { t } from "../lib/i18n";
import type { Arrival, Catalog } from "../lib/types";
import { RouteChip } from "./RouteChip";
import { StopCard } from "./StopCard";

const CATALOG: Catalog = {
  routes: [
    { id: "b1", short: "1", long: "Stop 0 - Stop 4", type: "bus" },
    { id: "t2", short: "2", long: "Depot - Square", type: "tram" },
  ],
  stops: [{ id: "s4", name: "Stop 4", code: "", lat: 49.84, lon: 24.03, routes: [0, 1] }],
};
const DUE_S = 300;

type Props = { children?: ReactNode; onWatch?: () => void; onLine?: () => void; watched?: boolean };

function elements(node: ReactNode): ReactElement<Props>[] {
  if (Array.isArray(node)) return node.flatMap(elements);
  if (!node || typeof node !== "object" || !("props" in node)) return [];
  const el = node as ReactElement<Props>;
  return [el, ...elements(el.props.children)];
}

const card = (arrivals: Arrival[] | undefined, watching: string[] = []) => {
  const on = { toggle: vi.fn(), route: vi.fn() };
  const props = {
    catalog: CATALOG,
    stop: 0,
    arrivals,
    pinned: false,
    onPin: () => {},
    watching: new Set(watching),
    onToggle: on.toggle,
    onRoute: on.route,
    onClose: () => {},
  };
  const chips = elements(StopCard(props)).filter((el) => el.type === RouteChip);
  return { on, chips };
};

describe("StopCard", () => {
  test("a due route's chip watches it and opens its line, as the chips under it do", () => {
    const arrivals = [{ route: 1, veh: 7, t: Date.now() / 1000 + DUE_S }];
    const { on, chips } = card(arrivals, ["b1"]);

    // the one due, then the two that call here
    expect(chips.map((c) => c.props.watched)).toEqual([false, true, false]);
    const [due, , tram] = chips;
    due!.props.onWatch!();
    expect(on.toggle).toHaveBeenCalledWith("t2");
    due!.props.onLine!();
    expect(on.route).toHaveBeenCalledWith(1);
    tram!.props.onLine!();
    expect(on.route).toHaveBeenCalledTimes(2);
  });

  const html = (arrivals: Arrival[], lowFloor = false) =>
    renderToStaticMarkup(
      <StopCard
        catalog={CATALOG}
        stop={0}
        arrivals={arrivals}
        pinned={false}
        onPin={() => {}}
        watching={new Set()}
        onToggle={() => {}}
        onRoute={() => {}}
        onClose={() => {}}
        lowFloor={lowFloor}
      />,
    );
  const soon = () => Date.now() / 1000 + DUE_S;

  test("says why a doubted time is amber, once, and nothing while none is", () => {
    const doubted = html([
      { route: 0, veh: 7, t: soon(), doubt: "stuck" },
      { route: 1, veh: 8, t: soon() },
    ]);

    expect(doubted.match(/text-amber-300/g)).toHaveLength(2); // the time and the note
    expect(doubted).toContain(t.doubt.stuck("1"));
    expect(html([{ route: 1, veh: 8, t: soon() }])).not.toContain("text-amber-300");
  });

  test("marks a low-floor vehicle only when asked to", () => {
    const low = [{ route: 1, veh: 8, t: soon(), low_floor: true }];

    expect(html(low, true)).toContain(`title="${t.lowFloor}"`);
    expect(html(low)).not.toContain(`title="${t.lowFloor}"`);
  });
});

