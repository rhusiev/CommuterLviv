/* The app shell, kept so a bad connection still opens the screen.
 *
 * There is no build-time list of files to precache: vite hashes every asset
 * name, so the worker would have to be generated to know them. It caches what
 * it serves instead, which reaches the same place after one visit and cannot
 * go stale against a build it was not told about.
 *
 * Three rules, and nothing else is touched:
 *   - a hashed asset under /assets/ never changes, so it is served from the
 *     cache and only fetched the first time
 *   - the document is fetched first and falls back to the cache, so a new
 *     deploy is picked up the moment the network allows it
 *   - /api and /ws are never cached: arrival times that are a minute old are
 *     worse than no arrival times, and a stale session would lie about who is
 *     signed in
 *
 * Basemap tiles are not cached here either. They come from another origin and
 * MapLibre already keeps them in the HTTP cache; duplicating that would put a
 * few hundred megabytes in a place nothing here prunes. */

const CACHE = "commuterlviv-v1";

self.addEventListener("install", () => self.skipWaiting());

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches
      .keys()
      .then((names) => Promise.all(names.filter((n) => n !== CACHE).map((n) => caches.delete(n))))
      .then(() => self.clients.claim()),
  );
});

async function keep(request, response) {
  if (response.ok) (await caches.open(CACHE)).put(request, response.clone());
  return response;
}

self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== location.origin) return;
  if (url.pathname.startsWith("/api") || url.pathname.startsWith("/ws")) return;

  if (url.pathname.startsWith("/assets/")) {
    e.respondWith(
      caches
        .match(e.request)
        .then((hit) => hit ?? fetch(e.request).then((r) => keep(e.request, r))),
    );
    return;
  }

  if (e.request.mode === "navigate") {
    e.respondWith(
      fetch(e.request)
        .then((r) => keep(e.request, r))
        .catch(() => caches.match(e.request).then((hit) => hit ?? caches.match("/"))),
    );
  }
});
