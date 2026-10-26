import type { ReactElement, ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, test, vi } from "vitest";
import { t } from "../lib/i18n";
import type { Route } from "../lib/types";
import { RouteChip } from "./RouteChip";

const ROUTE: Route = { id: "r1", short: "1A", long: "Stop 0 - Stop 4", type: "bus" };

type Props = {
  "aria-label"?: string;
  "aria-pressed"?: boolean;
  children?: ReactNode;
  onClick?: () => void;
  onContextMenu?: () => void;
};

function elements(node: ReactNode): ReactElement<Props>[] {
  if (Array.isArray(node)) return node.flatMap(elements);
  if (!node || typeof node !== "object" || !("props" in node)) return [];
  const el = node as ReactElement<Props>;
  return [el, ...elements(el.props.children)];
}

const chip = (watched: boolean) => {
  const on = { watch: vi.fn(), line: vi.fn() };
  const props = { route: ROUTE, watched, onWatch: on.watch, onLine: on.line };
  const buttons = elements(RouteChip(props)).filter((el) => el.type === "button");
  return { on, buttons, html: renderToStaticMarkup(<RouteChip {...props} />) };
};

describe("RouteChip", () => {
  test("watches the route from its body and opens the line from its other part", () => {
    const { on, buttons } = chip(false);

    const [body, line] = buttons;
    body!.props.onClick!();
    expect(on.watch).toHaveBeenCalledOnce();
    expect(on.line).not.toHaveBeenCalled();
    line!.props.onClick!();
    expect(on.line).toHaveBeenCalledOnce();
    expect(on.watch).toHaveBeenCalledOnce();
  });

  test("names the line part after the route, so either part can be found", () => {
    const { buttons } = chip(false);

    expect(buttons[1]!.props["aria-label"]).toBe(t.lineOf(ROUTE.short));
  });

  test("says whether the route is watched", () => {
    expect(chip(true).buttons[0]!.props["aria-pressed"]).toBe(true);
    expect(chip(false).buttons[0]!.props["aria-pressed"]).toBe(false);
    expect(chip(true).html).toContain(t.unwatchRoute);
    expect(chip(false).html).toContain(t.watchRoute);
  });

  test("has no hidden gesture", () => {
    for (const el of elements(RouteChip({ route: ROUTE, watched: true, onWatch() {}, onLine() {} }))) {
      expect(el.props.onContextMenu).toBeUndefined();
    }
  });
});
