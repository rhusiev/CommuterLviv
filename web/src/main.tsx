import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { api } from "./lib/api";
import { lang } from "./lib/i18n";
import { setSelfTiles } from "./lib/theme";
import "./app.css";

document.documentElement.lang = lang;

// Only from a built app: the dev server has no `sw.js`, and a worker caching
// its modules would serve them after they changed
if (import.meta.env.PROD && "serviceWorker" in navigator) {
  addEventListener("load", () => {
    void navigator.serviceWorker.register("/sw.js").catch(() => undefined);
  });
}

// Asked before the first render: the map reads the answer while it mounts
api.health().then((h) => setSelfTiles(h.tiles === true), () => {}).finally(() => {
  createRoot(document.getElementById("root")!).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
});
