import type { ReactElement, ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, test, vi } from "vitest";
import { HurryPill } from "./HurryPill";

const HINT = "Walk at least this fast";

type Props = {
  title?: string;
  children?: ReactNode;
  onClick?: (e: { stopPropagation: () => void }) => void;
};

const pill = (onWhy?: () => void) => {
  const props = { hint: HINT, onWhy, children: "5 km/h" };
  return {
    html: renderToStaticMarkup(<HurryPill {...props} />),
    el: HurryPill(props) as ReactElement<Props>,
  };
};

describe("HurryPill", () => {
  test("asks for its hint on a click, which goes no further", () => {
    const why = vi.fn();
    const stop = vi.fn();
    const { html, el } = pill(why);

    expect(html).toMatch(/^<button/);
    expect(el.props.title).toBe(HINT);
    el.props.onClick!({ stopPropagation: stop });
    expect(why).toHaveBeenCalledOnce();
    expect(stop).toHaveBeenCalledOnce();
  });

  test("only shows where it cannot say why, with no ⓘ", () => {
    const asked = pill(() => {}).html;
    const { html, el } = pill();

    expect(html).not.toContain("<button");
    expect(html).not.toContain(HINT);
    expect(el.props.onClick).toBeUndefined();
    expect(html.match(/<svg/g)).toHaveLength(1);
    expect(asked.match(/<svg/g)).toHaveLength(2);
  });
});
