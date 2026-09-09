/** What the address bar says the screen is showing.
 *
 * The point is a link somebody can send: "the 3A at Наукова" is a URL, not a
 * sequence of taps to describe. Everything here is feed ids for the same reason
 * pins are - a catalog position means nothing to the next person to open it.
 *
 * The path is left alone: `/join/<code>` is a different thing and the query is
 * written under it too, harmlessly.
 */
export type UrlState = {
  /** Route ids, or null when the address bar says nothing about routes and the
   * account's active set should decide */
  routes: string[] | null;
  stop: string | null;
  tab: "map" | "times" | "plan";
};

export function readUrl(): UrlState {
  const q = new URLSearchParams(location.search);
  const routes = q.get("routes");
  return {
    routes: routes === null ? null : routes.split(",").filter(Boolean),
    stop: q.get("stop"),
    tab: q.get("tab") === "times" ? "times" : q.get("tab") === "plan" ? "plan" : "map",
  };
}

/** Replaces rather than pushes: panning a map is not a page anyone wants the
 * back button to walk through, and the URL is only there to be copied. */
export function writeUrl(state: UrlState): void {
  const q = new URLSearchParams();
  if (state.routes?.length) q.set("routes", state.routes.join(","));
  if (state.stop !== null) q.set("stop", state.stop);
  if (state.tab !== "map") q.set("tab", state.tab);
  const search = q.toString();
  const next = location.pathname + (search ? `?${search}` : "");
  if (next !== location.pathname + location.search) history.replaceState(null, "", next);
}
