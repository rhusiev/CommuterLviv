import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { api } from "./lib/api";
import { lang } from "./lib/i18n";
import { setSelfTiles } from "./lib/theme";
import "./app.css";

// The document is served as Ukrainian; say so honestly when it is not, so a
// screen reader picks the right voice
document.documentElement.lang = lang;

// Only from a built app: the dev server has no `sw.js`, and a worker that
// cached the dev server's modules would serve them after they changed
if (import.meta.env.PROD && "serviceWorker" in navigator) {
  addEventListener("load", () => {
    void navigator.serviceWorker.register("/sw.js").catch(() => undefined);
  });
}

// Asked before the first render, because the map reads the answer while it
// mounts. A deployment that never answers keeps the public tile server, which
// is the only basemap it could have been serving anyway
api.health().then((h) => setSelfTiles(h.tiles === true), () => {}).finally(() => {
  createRoot(document.getElementById("root")!).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
});
