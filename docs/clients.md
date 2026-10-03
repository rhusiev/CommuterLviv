# The clients

## The web app

`web/` is what you look at: React 19 and Vite, a canvas of vehicles over a
MapLibre basemap.

```sh
cd web && npm install
npm run dev      # http://localhost:5173, proxying /api and /ws to the service
npm run build    # dist/, 69 kB gzipped, static, plus a lazy 265 kB of MapLibre
npm run preview  # http://localhost:5174, the built files with the same proxy
```

Lviv itself is MapLibre GL JS drawing VersaTiles OpenStreetMap vector tiles -
no key and no account - in one of eight styles picked in the layers panel:
colorful, natural, muted and gray, each light and dark (`THEMES` in
`web/src/lib/theme.ts`, `mapThemes` in `mobile/lib/src/map_theme.dart`). They
come from the deployment's own `/tiles` when `/api/health` says it has them,
and from `tiles.versatiles.org` otherwise - see
[the basemap](deployment.md#the-basemap). A style saved under one of the names
VersaTiles retired - shadow, eclipse, graybeard, neutrino - is read as its
successor.

Vehicles are coloured circles carrying their route number, with a wedge on the
rim pointing where they are going - solid while the vehicle is under way, an
outline while it stands, so a marker always says which way it faces without
claiming it is moving. Stops are small circles, drawn only for the routes you
have picked. Clicking one lists every route through it with the next
arrival for each, and pinning it puts it in the Times tab. Clicking a vehicle
asks the opposite question: `GET /api/vehicle?veh=<id>` answers with every stop
that vehicle is predicted to reach and when, out to the model's 45-minute
horizon, read off the same predictions the stop card shows - so the two cannot
disagree. A third tab plans a journey: tap where you are and where you are
going, and it answers with ways to get there, ranked by arrival - walk to a
stop, ride, maybe change, walk to the door. Named sets of routes -
one for work, one for home - live on the server, so they follow the account
rather than the browser. Serve `dist/` with a history fallback: every path has to
return `index.html`, or `/join/<code>` is a 404 and the invite link is dead.

An option can be followed. Follow on it moves to the map, turns on the dot
where you are and puts a card at the bottom that says what to do now: walk to
the stop, wait there, with when the vehicle is due, get off at the next, or that
you went past it or off the way. `Follower` in `web/src/lib/follow.ts`, ported
line for line to `mobile/lib/src/follow.dart`, works it out from the device's
own fixes and the vehicles as the map draws them, on the device: where you are
is never sent anywhere. Boarding is told from the fixes, not from a vehicle
coming near. You must have gone `BOARD_M` (100 m) along the ride's line, away
from the stop, faster than `WALK_MAX_MPS` (2.5 m/s), over at least
`BOARD_FIXES` (3) fixes. Only then is the vehicle you are on picked, as one of
the route's that kept pace with you - seen beside you for half the fixes and
moving at least half as far - and the planned one wins whenever it did. A tram standing at the stop as you ride away is passed over, and so is a
vehicle on another route. A ride whose vehicle is not found yet still counts as
a ride, and the vehicle is looked for again: the map draws the one you boarded
standing for some 10-20 s after it leaves - see
[findings](findings.md#the-feed-reports-a-vehicle-10-s-late-at-median). It
follows only while the app is open, because neither client asks for location
in the background.

One palette, two clients. `web/src/app.css` declares five colours, two radii and
one shadow in a Tailwind `@theme` block, and `mobile/lib/src/theme.dart` repeats
the same values; two of the colours, the near-black plate and the sky accent,
are the two colours in `web/public/icon.svg`, so both apps are the colour of
their own icon. Above that sit the utilities everything is built from - `panel`,
`bar`, `fab`, `inset-panel`, `btn`, `btn-quiet`, `field`, `field-bar` - and each
is translucent, blurred, a hairline ring and a soft shadow rather than a border,
because the map underneath is the context. Nothing outside `app.css` names a
`slate-*` shade for a surface.

Nothing is docked to an edge. The map is the whole window in both clients and
every piece of chrome floats over it: a search bar and a menu at the top, the
map/times/plan pill at the bottom where a thumb is, round buttons for locate and
zoom, and cards that rise off the bottom rather than out of it. That is why the
web layout is one `relative` box of absolutely positioned pieces instead of a
column, and why the phone's `Scaffold` has neither an `appBar` nor a
`bottomNavigationBar`: `floatingTop` and `floatingBottom` in `theme.dart` are
what anything scrollable uses to clear the two floating bars.

What goes where is decided by what a control does, not by how often it is
wanted. Routes choose what is tracked and open the routes panel. Layers change
what the map draws - the route lines, the traffic, the basemap - and live in one
sheet behind a layers button, whose icon is lit while anything in it is on.
Everything belonging to the account rather than to the map - what is saved, the
language, the server, signing out - lives behind an account button, with signing
out below a rule so it is never the tap next to anything else. Nothing that is a
toggle and nothing that signs you out sits loose on the map. That is
`LayersSheet` and `AccountSheet` in `mobile/lib/src/sheets.dart`, and
`LayersPanel.tsx` and `AccountMenu.tsx` on the web.

A route is named the same way everywhere: the kind of vehicle as a glyph, then
the number. The city writes the kind as the letter in front of the number - `А25`
is a bus, `Т07` a tram, `Тр33` a trolleybus - which only helps a reader who knows
that and reads Cyrillic, so `routeNumber` in `web/src/lib/sprites.ts` and
`mobile/lib/src/map_theme.dart` strips it and `RouteBadge` draws it instead. The
glyphs are three line drawings in `RouteBadge.tsx` and `route_badge.dart`, the
same 24-unit box in both, because no icon set carries a trolleybus. On the map
there is no room for a glyph in a 26 px circle, so the badge is the number alone
and the hue carries the kind - which it already did.

`tool/icons.sh` draws every icon of all three clients from that one SVG,
including the `maskable` PNG the manifest points at, which is framed like the
Android adaptive icon because a browser crops it.

It installs. `web/public/manifest.webmanifest` and `web/public/sw.js` make it a
progressive web app: an icon on the home screen, no browser chrome, and a shell
that opens without the network. The worker caches only what it has already
served - hashed assets under `/assets/` for good, the document network-first -
and never `/api` or `/ws`, because a minute-old arrival time is worse than none
and a cached session would lie about who is signed in. Offline it opens and says
the service is not answering, which is the truth: the times come from the socket.

The language is Ukrainian, with English for a browser that asks for it;
`web/src/lib/i18n.ts` holds both dictionaries and the picker is in the route
panel. Changing it reloads the page; the phone app, which shares the same keys,
switches without a restart.

Smoothness is the reason for the shape of the code. Positions arrive every five
seconds, and between them each vehicle is interpolated towards where the server
last put it, eased over 1.2 s, with the heading taking the short way round.
Nothing about a position passes through React: the socket writes into a plain
`Map`, the animation loop reads it, and React only ever hears about the
connection, the arrivals and the vehicle count. Route badges are rendered once
into offscreen canvases, so drawing four hundred vehicles is four hundred blits
rather than four hundred text layouts. The overlay draws inside MapLibre's own
render pass and projects points with the same Web Mercator formula the basemap
uses, so panning moves the city and the vehicles in the same frame.

## The phone app

`mobile/` is the same client again, in Flutter, for Android and iOS. It adds no
endpoint and no model - the browser and the phone see the same city, the same
route sets and the same predictions, and the same journey planner behind the
third choice in the tab pill. Both also carry the same three views added since:
a saved list where a place can be renamed or dropped, a search that finds
addresses and shops as well as stop names, traffic drawn over the streets
the model can see, and following a journey as you travel it.

```sh
cd mobile && flutter pub get
flutter test     # the wire decoder, against bytes commuterlviv/live/wire.py made
flutter run --dart-define=COMMUTERLVIV_BASE=http://10.0.2.2:8099
flutter build apk --release
```

Without that `--dart-define` the app talks to `https://commuterlviv.r1a.nl`, which is
where it is published: an F-Droid build passes no defines, so the default has to
be the real server. The sign-in screen takes any other address and remembers it.

The shape of the code is the shape of the web app's, for the same reason. Every
vehicle and every stop is one `CustomPaint` repainted from a `Ticker`, not four
hundred widgets; positions are eased between the five-second frames; and the
route badge for each route is laid out once into a `ui.Paragraph` and drawn
thereafter, which is what the offscreen badge canvases do in the browser.

It is built to be publishable on F-Droid, which is why it is Flutter and not
Expo: F-Droid builds from source and takes no proprietary SDK, so there is no
Play Services, no Firebase and no keyed map SDK anywhere in the tree. The
basemap is the same VersaTiles OpenStreetMap tiles, rendered on the device.
The one cost of that rule is paid by the locate-me button, which is a
hand-written channel - AOSP's `LocationManager` on Android, `CoreLocation` on
iOS - rather than the usual package, which brings Play Services with it; see
`mobile/README.md`. The app asks for the internet permission, and
for location on the first press of that button or of Follow; the fix never
leaves the phone.

The service needs one line for it: `app://commuterlviv` in `COMMUTERLVIV_ORIGINS`. The
app is not a web page and has no web origin, and that scheme is one no browser
will ever mint, so listing it cannot widen what a web page may do.
