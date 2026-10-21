import type { ReactElement, ReactNode } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, test, vi } from "vitest";
import { t } from "../lib/i18n";
import { PlaceCard } from "./PlaceCard";

const RYNOK = { name: "Ринок", where: "Львів, Галицький район", lat: 49.8419, lon: 24.0315 };

type Props = { title?: string; children?: ReactNode; onClick?: () => void };

/** The card's own elements, with the props it gave them, outermost first */
function elements(node: ReactNode): ReactElement<Props>[] {
  if (Array.isArray(node)) return node.flatMap(elements);
  if (!node || typeof node !== "object" || !("props" in node)) return [];
  const el = node as ReactElement<Props>;
  return [el, ...elements(el.props.children)];
}

const card = (isSaved: boolean, on: { save?: () => void; go?: () => void } = {}) => {
  const props = {
    place: RYNOK,
    isSaved,
    onSave: on.save ?? (() => {}),
    onGo: on.go ?? (() => {}),
    onClose: () => {},
  };
  return { html: renderToStaticMarkup(<PlaceCard {...props} />), tree: elements(PlaceCard(props)) };
};

describe("PlaceCard", () => {
  test("names a found place over its address and offers to save it", () => {
    const save = vi.fn();
    const { html, tree } = card(false, { save });

    expect(html).toContain(RYNOK.name);
    expect(html).toContain(RYNOK.where);
    tree.find((el) => el.props.title === t.savePlace)!.props.onClick!();
    expect(save).toHaveBeenCalledOnce();
  });

  test("says a saved place is saved, with nothing to save again", () => {
    const { html } = card(true);

    expect(html).toContain(t.saved);
    expect(html).not.toContain(RYNOK.where);
    expect(html).not.toContain(t.savePlace);
  });

  test("plans the way there", () => {
    const go = vi.fn();
    const { tree } = card(false, { go });

    tree.find((el) => [el.props.children].flat().includes(t.getHere))!.props.onClick!();
    expect(go).toHaveBeenCalledOnce();
  });
});
