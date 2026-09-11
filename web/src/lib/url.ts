/** What the address bar says the screen is showing, as feed ids: a catalog
 * position means nothing to whoever the link is sent to. The path is left
 * alone, so `/join/<code>` keeps working with the query written under it. */
export type UrlState = {
  /** Null when the address bar says nothing and the active set should decide */
  routes: string[] | null;
  stop: string | null;
  route: string | null;
  tab: "map" | "times" | "plan" | "route";
};

const TABS: UrlState["tab"][] = ["map", "times", "plan", "route"];

export function readUrl(): UrlState {
  const q = new URLSearchParams(location.search);
  const routes = q.get("routes");
  return {
    routes: routes === null ? null : routes.split(",").filter(Boolean),
    stop: q.get("stop"),
    route: q.get("route"),
    tab: TABS.includes(q.get("tab") as UrlState["tab"]) ? (q.get("tab") as UrlState["tab"]) : "map",
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
