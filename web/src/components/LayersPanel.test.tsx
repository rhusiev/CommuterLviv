import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, test, vi } from "vitest";
import type { Lang } from "../lib/i18n";

/** The panel as drawn in `lang`, which the strings module reads as it loads */
async function panel(lang: Lang) {
  localStorage.setItem("commuterlviv.lang", lang);
  vi.resetModules();
  const { LayersPanel } = await import("./LayersPanel");
  const { THEMES } = await import("../lib/theme");
  const props = {
    lines: false,
    onLines: () => {},
    traffic: false,
    onTraffic: () => {},
    theme: THEMES[0]!,
    onTheme: () => {},
  };
  return renderToStaticMarkup(<LayersPanel {...props} />);
}

describe("LayersPanel", () => {
  test("names the basemaps in Ukrainian", async () => {
    const html = await panel("uk");
    expect(html).toContain("Кольорова темна");
    expect(html).toContain("Сіра");
    expect(html).not.toContain("Gray");
  });

  test("names the basemaps in English", async () => {
    const html = await panel("en");
    expect(html).toContain("Colorful dark");
    expect(html).toContain("Gray");
  });

  test("heads the basemaps as the app does", async () => {
    expect(await panel("en")).toContain(">Map style<");
    expect(await panel("uk")).toContain(">Вигляд мапи<");
  });
});
