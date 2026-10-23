/** What the address bar says the screen is showing, as feed ids: a catalog
 * position means nothing to whoever the link is sent to. The path is left
 * alone, so `/join/<code>` keeps working with the query written under it. */
export type UrlState = {
  /** Null when the address bar says nothing and the active set should decide */
  routes: string[] | null;
  stop: string | null;
  route: string | null;
  tab: Tab;
};

export type Tab = "map" | "plan" | "mine" | "route";

const TABS: Tab[] = ["map", "plan", "mine", "route"];

/** Tabs an older link may name, and the tab that holds what they held now */
const MOVED: Record<string, Tab> = { times: "mine", saved: "mine" };

/** The tab a link's `tab` names, an old name read as its successor */
export function tabOf(named: string | null): Tab {
  if (named === null) return "map";
  if (Object.hasOwn(MOVED, named)) return MOVED[named]!;
  return TABS.includes(named as Tab) ? (named as Tab) : "map";
}

export function readUrl(): UrlState {
  const q = new URLSearchParams(location.search);
  const routes = q.get("routes");
  return {
    routes: routes === null ? null : routes.split(",").filter(Boolean),
    stop: q.get("stop"),
    route: q.get("route"),
    tab: tabOf(q.get("tab")),
  };
}

/** Replaces rather than pushes: these changes are not back-button history */
export function writeUrl(state: UrlState): void {
  const q = new URLSearchParams();
  if (state.routes?.length) q.set("routes", state.routes.join(","));
  if (state.stop !== null) q.set("stop", state.stop);
  if (state.route !== null) q.set("route", state.route);
  if (state.tab !== "map") q.set("tab", state.tab);
  const search = q.toString();
  const next = location.pathname + (search ? `?${search}` : "");
  if (next !== location.pathname + location.search) history.replaceState(null, "", next);
}
