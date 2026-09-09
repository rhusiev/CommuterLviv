import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { lang } from "./lib/i18n";
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

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
