"""Drives headless chromium over CDP to check the web app for real.

No playwright here - the debugging protocol is a websocket that takes JSON, and
everything this needs is a handful of its methods.

Takes one unspent invite code, and needs both the service and `npm run dev` up:

    python3 -m commuterlviv admin invite
    python3 check_web.py <code>

It registers a fresh `browser_<timestamp>` account each run, so it leaves one
behind but never collides with itself. COMMUTERLVIV_CHECK_WEB overrides the vite
origin - it must be one of COMMUTERLVIV_ORIGINS, and `localhost` and `127.0.0.1`
are different origins to the browser. Screenshots land in /tmp/shot-*.png
"""

import asyncio, base64, inspect, json, os, shutil, subprocess, sys, tempfile, time, urllib.request
import websockets

PORT = 9222
BASE = os.environ.get("COMMUTERLVIV_CHECK_WEB", "http://localhost:5173")
CODE = sys.argv[1]
USER, PASS = f"browser_{int(time.time())}", "a longer passphrase here"

failed = []


def check(name, ok, extra=""):
    print(("  ok   " if ok else "  FAIL ") + name + (f"  [{extra}]" if extra and not ok else ""))
    if not ok:
        failed.append(name)


class Page:
    def __init__(self, ws):
        self.ws = ws
        self.id = 0
        self.pending = {}
        self.errors = []
        self.requests = []
        self.stage = "startup"

    def step(self, name):
        self.stage = name
        print("\n" + name)

    async def pump(self):
        async for raw in self.ws:
            msg = json.loads(raw)
            if "id" in msg:
                fut = self.pending.pop(msg["id"], None)
                if fut and not fut.done():
                    fut.set_result(msg)
            elif msg["method"] == "Target.attachedToTarget":
                # No `call` here: this loop is what reads the answers, so
                # waiting for one from inside it would wait forever
                self.id += 1
                await self.ws.send(json.dumps({"id": self.id, "method": "Network.enable",
                                               "params": {}, "sessionId": msg["params"]["sessionId"]}))
            elif msg["method"] == "Network.requestWillBeSent":
                self.requests.append(msg["params"]["request"]["url"])
            elif msg["method"] == "Runtime.exceptionThrown":
                d = msg["params"]["exceptionDetails"]
                self.errors.append(f"[{self.stage}] " + d.get("text", "") + " " + str(d.get("exception", {}).get("description", "")))
            elif msg["method"] == "Runtime.consoleAPICalled" and msg["params"]["type"] == "error":
                self.errors.append(f"[{self.stage}] " + " ".join(str(a.get("value", a.get("description", ""))) for a in msg["params"]["args"]))

    async def call(self, method, **params):
        self.id += 1
        fut = asyncio.get_running_loop().create_future()
        self.pending[self.id] = fut
        await self.ws.send(json.dumps({"id": self.id, "method": method, "params": params}))
        return (await asyncio.wait_for(fut, 90)).get("result", {})

    async def js(self, expr):
        r = await self.call("Runtime.evaluate", expression=expr, awaitPromise=True, returnByValue=True)
        if "exceptionDetails" in r:
            d = r["exceptionDetails"]
            raise RuntimeError(d.get("text", "") + " " +
                               str(d.get("exception", {}).get("description", "")))
        return r["result"].get("value")

    async def until(self, expr, what, timeout=20):
        return await self.wait(lambda: self.js(expr), what, timeout)

    async def wait(self, cond, what, timeout=20):
        """`cond` may answer straight away or with something to await."""
        for _ in range(timeout * 5):
            got = cond()
            if inspect.isawaitable(got):
                got = await got
            if got:
                return True
            await asyncio.sleep(0.2)
        check(what, False, "timed out")
        return False

    async def submit(self, user, password, remember=False):
        """React listens for `input`, and setting `.value` does not raise one -
        hence the native setter and the hand-made event."""
        await self.js("""(() => {
          const set = (el, v) => {
            Object.getOwnPropertyDescriptor(Object.getPrototypeOf(el), 'value').set.call(el, v);
            el.dispatchEvent(new Event('input', {bubbles: true}));
          };
          const f = document.querySelector('form');
          const [u, pw] = f.querySelectorAll('input:not([type=checkbox])');
          set(u, %s); set(pw, %s);
          const cb = f.querySelector('input[type=checkbox]');
          if (%s && cb && !cb.checked) cb.click();
          f.querySelector('button[type=submit], button').click();
        })()""" % (json.dumps(user), json.dumps(password), "true" if remember else "false"))

    async def shot(self, path):
        r = await self.call("Page.captureScreenshot", format="png")
        open(path, "wb").write(base64.b64decode(r["data"]))


async def main():
    # A fresh profile per run: a reused one carries the previous run's session
    # cookie, and then the invite link renders the map instead of the form
    profile = tempfile.mkdtemp(prefix="commuterlviv-cdp-")
    proc = subprocess.Popen(
        ["chromium-browser", "--headless=new", f"--remote-debugging-port={PORT}",
         f"--user-data-dir={profile}", "--no-first-run", "--disable-gpu",
         # MapLibre needs WebGL, and headless chromium only gives it through
         # software rendering once this flag says that is acceptable
         "--enable-unsafe-swiftshader",
         "--window-size=1280,900", "about:blank"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(100):
            try:
                tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{PORT}/json/list"))
                page = next(t for t in tabs if t["type"] == "page")
                break
            except Exception:
                await asyncio.sleep(0.2)
        else:
            raise SystemExit("chromium never came up")

        async with websockets.connect(page["webSocketDebuggerUrl"], max_size=None) as ws:
            p = Page(ws)
            pump = asyncio.create_task(p.pump())
            await p.call("Page.enable")
            await p.call("Runtime.enable")
            await p.call("Network.enable")
            # maplibre's worker is a target of its own, and its requests reach
            # this websocket only once we attach to it
            await p.call("Target.setAutoAttach", autoAttach=True, waitForDebuggerOnStart=False, flatten=True)

            p.step("taking up the invite link")
            await p.call("Page.navigate", url=f"{BASE}/join/{CODE}")
            if not await p.until("!!document.querySelector('form')", "the join form renders"):
                return 1
            check("the form knows it is an invite",
                  "invit" in (await p.js("document.body.innerText")).lower()
                  or "join" in (await p.js("document.body.innerText")).lower())
            await p.submit(USER, PASS, remember=True)
            ok = await p.until("document.querySelectorAll('canvas').length > 0", "the map appears after joining")
            check("registering through the link signed us in", bool(ok))

            p.step(f"signing out and back in as {USER}")
            await p.js("[...document.querySelectorAll('button')].find(b => /out$/.test(b.textContent)).click()")
            await p.until("!!document.querySelector('form')", "the sign-in form comes back")
            await p.submit(USER, PASS)
            check("signing in as an existing account works",
                  await p.until("document.querySelectorAll('canvas').length > 0", "the map renders"))

            p.step("picking routes")
            await p.js("[...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Routes').click()")
            await p.until("document.querySelectorAll('aside button').length > 5", "the route panel opens")
            # Every route, not a handful: after dark most routes have nothing on
            # them, and a check that picked the first six failed for no reason
            # other than the hour it was run at
            picked = await p.js("""(() => {
              const chips = [...document.querySelectorAll('aside [data-chips] button')];
              chips.forEach(b => b.click());
              return chips.map(b => b.textContent.trim());
            })()""")
            check("route chips are listed and clickable", bool(picked), str(picked[:6]))
            print(f"   picked {len(picked)} routes:", " ".join(picked[:8]), "…")
            await p.js("[...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Routes').click()")

            got = await p.until("+document.body.innerText.match(/(\\d+) vehicles/)[1] > 0",
                                "vehicles arrive over the socket", 150)
            check("vehicles arrive over the socket", bool(got))
            n1 = await p.js("document.body.innerText.match(/(\\d+) vehicles/)[1]")
            print("   vehicles on the map:", n1)
            check("the connection dot is green",
                  await p.js("!!document.querySelector('[title=live]')"))

            p.step("the basemap")
            # The tiles are asked for by maplibre's worker, whose requests the
            # page never sees, so this counts what the protocol reports rather
            # than what `performance` knows. A style that loads and then asks
            # for no tile at all is that worker broken, which is what this
            # catches - it has been broken twice, differently, in dev and in
            # the build
            tiles = lambda: [u for u in p.requests if "versatiles.org/tiles" in u]
            check("the city's tiles are fetched",
                  await p.wait(tiles, "tiles are requested", 60))
            print("   tiles requested:", len(tiles()))

            # `window.lvivMap` is a development handle; a build does not set one
            if await p.js("!!window.lvivMap"):
                await p.until("lvivMap.isStyleLoaded()", "the style loads", 60)
                drawn = await p.js("lvivMap.queryRenderedFeatures().length")
                check("the city is rendered under the vehicles", drawn > 100, str(drawn))
                print("   rendered features:", drawn)
                # The overlay projects lat/lon itself rather than calling
                # map.project per vehicle per frame, so the two must agree
                off = await p.js("""(() => {
                  const m = lvivMap, c = m.getCenter(), W = 512 * 2 ** m.getZoom();
                  const el = m.getCanvas(), w = el.clientWidth, h = el.clientHeight;
                  const mx = lon => (lon + 180) / 360;
                  const my = lat => { const s = Math.sin(lat * Math.PI / 180);
                                      return 0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI); };
                  const ox = mx(c.lng) * W - w / 2, oy = my(c.lat) * W - h / 2;
                  let worst = 0;
                  for (const [lat, lon] of [[49.842, 24.032], [49.80, 23.95], [49.88, 24.11]]) {
                    const p = m.project([lon, lat]);
                    worst = Math.max(worst, Math.abs(p.x - (mx(lon) * W - ox)),
                                            Math.abs(p.y - (my(lat) * W - oy)));
                  }
                  return worst;
                })()""")
                check("the overlay projection matches maplibre", off < 0.5, f"{off} px apart")
            else:
                print("   a build, not the dev server: no map handle to ask for more")

            p.step("the map moves")
            sum_px = """(() => { const c = [...document.querySelectorAll('canvas')].at(-1);
              return c.getContext('2d').getImageData(0, 0, c.width, c.height).data.reduce((s, v) => s + v, 0); })()"""
            a = await p.js(sum_px)
            check("the overlay is drawing something", a > 0)
            # Software WebGL renders at a few frames a second and a vehicle
            # waiting at a stop does not move at all, so this waits rather than
            # comparing two frames three seconds apart
            b = a
            for _ in range(20):
                await asyncio.sleep(0.5)
                b = await p.js(sum_px)
                if b != a:
                    break
            check("the overlay redraws as the vehicles move", a != b, f"{a} == {b}")

            await p.shot("/tmp/shot-map.png")

            p.step("clicking a stop")
            # The overlay does not take pointer events - MapLibre owns them - so
            # this finds a stop by its fill and lets the browser deliver a real
            # click at those coordinates
            hit = await p.js("""(() => {
              const c = [...document.querySelectorAll('canvas')].at(-1);
              const r = c.getBoundingClientRect();
              const dpr = devicePixelRatio;
              const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
              for (let py = 0; py < c.height; py++) {
                for (let px = 0; px < c.width; px++) {
                  const o = (py * c.width + px) * 4;
                  if (d[o] === 0xcf && d[o+1] === 0xd8 && d[o+2] === 0xe3) {
                    return [r.left + px / dpr, r.top + py / dpr];
                  }
                }
              }
              return null;
            })()""")
            if hit:
                for kind in ("mousePressed", "mouseReleased"):
                    await p.call("Input.dispatchMouseEvent", type=kind, x=hit[0], y=hit[1],
                                 button="left", buttons=1, clickCount=1)
            await asyncio.sleep(0.5)
            card = hit is not None and "pin" in (await p.js("document.body.innerText")).lower()
            check("clicking a stop opens its card", card)
            if hit:
                print("   hit at", hit)
                print("   card says:", (await p.js("document.body.innerText")).split("\n")[-8:])
                await p.shot("/tmp/shot-stop.png")
            if card:
                await p.js("[...document.querySelectorAll('button')].find(b => /pin/i.test(b.textContent)).click()")

            p.step("the times tab")
            await p.js("[...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Times').click()")
            await asyncio.sleep(1)
            text = await p.js("document.body.innerText")
            check("the times tab shows the pinned stop", "Nothing pinned" not in text, text[:200])
            print("   " + " | ".join(t for t in text.split("\n")[2:10] if t.strip()))
            await p.shot("/tmp/shot-times.png")

            p.step("searching for a stop")
            # React owns the input's value, so a plain assignment is overwritten
            # on the next render; the native setter plus an input event is what
            # the library itself listens for
            await p.js("""(() => {
              const el = document.querySelector('input[placeholder="Find a stop"]');
              const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
              set.call(el, 'вул');
              el.dispatchEvent(new Event('input', { bubbles: true }));
            })()""")
            await asyncio.sleep(0.4)
            name = await p.js("document.querySelector('[data-hit]')?.dataset.hit ?? null")
            check("typing a name lists matching stops", bool(name), str(name))
            if name:
                await p.js("document.querySelector('[data-hit]').click()")
                await asyncio.sleep(0.6)
                text = await p.js("document.body.innerText")
                check("picking a hit opens that stop's card", name in text,
                      f"{name!r} not in the card")
                await p.shot("/tmp/shot-search.png")

            p.step("changing the map theme")
            await p.js("[...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Routes').click()")
            await asyncio.sleep(0.3)
            await p.js("[...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Neutrino').click()")
            light = await p.until(
                "!![...document.querySelectorAll('canvas')].length && localStorage.getItem('commuterlviv.theme') === 'neutrino'",
                "the theme is stored")
            check("a light theme is chosen and remembered", light)
            # The overlay repaints in the light palette, so the dark stop fill is
            # gone from the canvas the click test found stops in. Only its absence
            # is asserted: whether any stop is in view depends on where the search
            # flew the camera, and a check that needs one would be flaky
            await asyncio.sleep(1.5)
            fills = await p.js("""(() => {
              const c = [...document.querySelectorAll('canvas')].at(-1);
              const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data;
              let dark = 0, light = 0;
              for (let o = 0; o < d.length; o += 4) {
                if (d[o] === 0xcf && d[o+1] === 0xd8 && d[o+2] === 0xe3) dark++;
                else if (d[o] === 0x33 && d[o+1] === 0x41 && d[o+2] === 0x55) light++;
              }
              return [dark, light];
            })()""")
            check("the overlay repaints for the new theme", fills[0] == 0,
                  f"{fills[0]} dark pixels left")
            print(f"   {fills[1]} light stop pixels drawn")
            await p.shot("/tmp/shot-theme.png")
            await p.js("[...document.querySelectorAll('button')].find(b => b.textContent.trim() === 'Shadow').click()")

            p.step("the session survives a reload")
            await p.call("Page.navigate", url=BASE + "/")
            check("still signed in after a reload",
                  await p.until("document.querySelectorAll('canvas').length > 0 || !!document.querySelector('form')", "page settles")
                  and await p.js("!document.querySelector('form')"))

            print()
            real = [e for e in p.errors if "favicon" not in e.lower()]
            check("no console errors", not real, " / ".join(real[:3]))
            pump.cancel()
        return 1 if failed else 0
    finally:
        proc.terminate()
        shutil.rmtree(profile, ignore_errors=True)
        print(f"\n{len(failed)} failed" if failed else "\nall browser checks passed")
        for f in failed:
            print("  -", f)


sys.exit(asyncio.run(main()))
