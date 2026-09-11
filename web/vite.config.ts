import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "vite";

// The dev server proxies instead of pointing the app at :8099 directly, so the
// browser sees one origin and the session cookie behaves as it will in
// production - a cross-origin dev setup would need SameSite=None to work at all
const API = process.env.COMMUTERLVIV_API ?? "http://127.0.0.1:8099";
const proxy = {
  "/api": { target: API, changeOrigin: false },
  "/ws": { target: API, ws: true, changeOrigin: false },
};

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: { port: 5173, proxy },
  // `vite preview` is how the built app gets checked before it is deployed, so
  // it needs the same proxy - on its own port, to leave the dev server running
  preview: { port: 5174, proxy },
  // maplibre starts its worker as a module unless the url ends in `.cjs`, so
  // the worker bundle has to be modules too
  worker: { format: "es" },
  build: { target: "es2022" },
});
