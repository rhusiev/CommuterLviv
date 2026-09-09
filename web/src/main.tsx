import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { lang } from "./lib/i18n";
import "./app.css";

// The document is served as Ukrainian; say so honestly when it is not, so a
// screen reader picks the right voice
document.documentElement.lang = lang;

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
