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
`web/src/lib/theme.ts`, `mapThemes` in `mobile/lib/src/map_theme.dart`), named
in the language's strings (`themeNames`). They
come from the deployment's own `/tiles` when `/api/health` says it has them,
and from `tiles.versatiles.org` otherwise - see
[the basemap](deployment.md#the-basemap). A style saved under one of the names
VersaTiles retired - shadow, eclipse, graybeard, neutrino - is read as its
successor.

Vehicles are coloured circles carrying their route number, with a wedge on the
rim pointing where they are going - solid while the vehicle is under way, an
outline while it stands, so a marker always says which way it faces without
claiming it is moving. Stops are small circles, drawn for the routes you have
picked. From zoom 16 (`ALL_STOPS_ZOOM`, 17 in the app's tiles) every other stop
is drawn too, faint, and opens its card like the rest, so a stop can be looked
up without watching a route first. The routes to pick are in the Lines tab,
grouped under buses, trams and trolleybuses, because tram 1 and bus 1 are
different lines. A route is drawn as the same split chip wherever it shows -
the Lines tab, a stop's card, the Mine tab's pinned stops, a vehicle's card: a
click on its body watches it or stops watching it, and the `›` beside it opens
its line. A chip hides nothing behind a right click or a long press. On the map
itself a right click, or a long press on a phone, opens a menu for that point:
save it under a name typed into the menu, plan the way there or from there, or
list the stops within 2 km of it in the search, as ◎ does for where you are.
A place is known by its name, so a name another saved place goes by is said to
replace that place: in the menu under the name typed, and before a save from the
search, a card or the planner in a dialog that saves only on "Replace". Saving a
place again where it stands asks nothing.
Clicking a stop opens its card: the next arrival of each route due there, and
under "Calls here" every route through it. Pinning it
puts it in the Mine tab. Clicking a vehicle
asks the opposite question: `GET /api/vehicle?veh=<id>` answers with every stop
that vehicle is predicted to reach and when, out to the model's 45-minute
horizon, read off the same predictions the stop card shows - so the two cannot
disagree. The Journey tab plans a journey: tap where you are and where you are
going, and it answers with ways to get there, ranked by arrival - walk to a
stop, ride, maybe change, walk to the door. An end put where you are reads
"Where I am" in its field rather than its coordinates. A point nothing named,
in its field and at the top of the map's menu, is called by the stop within
300 m nearest to it ("Near Stop 4"), and only past that by its coordinates; the
app does the same, and also under Mine. Already on a vehicle, "I'm on it"
on its card plans from on board it: the From field shows it, there is no time
to leave at, and only its id is sent (docs/service.md). It lasts only while
the planner is open: leaving the planner, or following a journey, drops it, as
the vehicle goes on without the planner. Named sets of routes -
one for work, one for home - live on the server, so they follow the account
rather than the browser. Serve `dist/` with a history fallback: every path has to
return `index.html`, or `/join/<code>` is a 404 and the invite link is dead.

An option the planner lists is one click target until it is drawn on the map: a
click anywhere on it draws it and opens it, and nothing on it opens anything
else. Folded, it says in words what is worth knowing - the hurry pill, its
weakest ride's note on how sure its time is, and how many backups it has, in
the green of the backups button it opens into. Its strip of legs gives a walk
its minutes and a ride the minutes waited for it, by a clock, then its badge and
the minutes ridden; opened, a wait of a minute or more (`WAIT_MIN_S`, the
follow card's) is a row of its own before the ride, and the ride says "Ride N
min". Its
summary row stays the one target that folds it again and never turns into
anything else. Opened, every control below it is drawn as one and is at least
44 px tall: a stop's row has a chevron and opens the stop's card, a route's
badge sits in a ring with a map and opens its line, "N backups ›" lists the
backups, and Follow follows it. A note and the hurry pill say why in place,
under them, with nothing to tap for it. The app does the same
(`mobile/README.md`). Drawing an option also frames the map on it - its
walks, its rides and the stops they meet - and rings the vehicles its rides are
planned on (`riddenBy`, from each ride's `veh`) in the colour of the location
dot, fading the other vehicles of its routes. The framing, and a line's from the
Lines tab, keeps clear of the panel open over the map. The app keeps it above
its bottom panel. The web uses the widest strip the panel leaves free, measured as
the fit is made, or the whole map when no strip is 120 px wide past its
padding (`lib/padding.ts`).

An option can be followed. Follow on it moves to the map, turns on the dot
where you are and puts a card at the bottom that says what to do now: walk to
the stop, wait there, with when the vehicle is due, get off at the next, or that
you went past it or off the way. The map keeps the dot in the middle with each
fix, through a zoom too. A pan by hand lets go of it, so the way ahead can be
looked at, and the locate button takes it back. `Follower` in `web/src/lib/follow.ts`, ported
line for line to `mobile/lib/src/follow.dart`, works it out from the device's
own fixes and the vehicles as the map draws them, on the device: where you are
is never sent anywhere. Boarding is told from the fixes, not from a vehicle
coming near. You must have gone `BOARD_M` (100 m) along the ride's line, away
from the stop, faster than `WALK_MAX_MPS` (2.5 m/s), over at least
`BOARD_FIXES` (3) fixes. Only then is the vehicle you are on picked, as one of
the route's that kept pace with you - seen beside you for half the fixes and
moving at least half as far - and the planned one wins whenever it did. A tram
standing at the stop as you ride away is passed over, and so is a vehicle on
another route. A ride whose vehicle is not found yet still counts as a ride,
and the vehicle is looked for again: the map draws the one you boarded standing
for some 10-20 s after it leaves, because a fix reaches the server about 10 s
after the vehicle took it at the median and 19 s at the 90th percentile, and
the server holds a vehicle still until a fix shows it moving (`_moving` in
`commuterlviv/live/state.py`). The vehicle found is kept only while it stays
beside you on the leg's route, and is looked for again after `LOST_FIXES` (5)
fixes without it. That also covers its id coming back on another vehicle: the
server frees the id of a vehicle quiet for 300 s (`GAP_RESET`) and hands freed
ids out again oldest first. The card says to get ready to get off once the ride
is past the last stop before yours, from the stops the server sends with each
ride (docs/service.md), and right from boarding on a ride of one stop. A ride
without them - from a reported journey, say, or an older server - gets ready
`SOON_M` (400 m) before the stop instead.

A tap on the card lists every step of the journey with its start and end:
each walk, each wait of a minute or more (`WAIT_MIN_S`) at a stop, and each
ride with its route and its two stops, the step under way marked. The rows are
built by `rows()` in `web/src/lib/legs.ts`, ported to `mobile/lib/src/legs.dart`.

The card also watches the next ride to board. `Follower.reach` times when you
get to its stop: on foot, from the metres left at the usual walking speed and
at the hurrying one (the usual, if hurrying is off); on a ride, from when the
vehicle ridden is predicted at the stop to get off at, plus the walks to the
next ride. `judge` sets that against the vehicle's predicted arrival, or the
timetable when it is not tracked: caught at the usual pace, caught only by
hurrying - or, for a tracked vehicle, within `GRACE_S` (10 s) of it, as the
planner does - or missed. Predictions jump, so `Watch` says a worse word only
once it has held for 10 s, or at once within 120 s of leaving; a better word is
said at once. It judges again with each fix, each word of arrivals and every
second, so a held word is not left waiting for the next fix. Hurrying is urged
only on foot, with an amber pill giving the pace that gets to the stop with time
to spare, from the metres left (`needKmh`). The time to spare is half
(`MARGIN_SHARE`, chosen, not derived) of the slack the planner keeps for a
change that far ahead (`CHANGE_AHEAD`/`CHANGE_SLACK`, copied from
`commuterlviv/plan/scan.py`), as a vehicle comes early as well as late. When that
pace is over 12 km/h (`HURRY_KMH`), the pill gives the one that gets there as
the vehicle leaves; either is rounded up to 0.5 km/h. A hurry option in the
planner carries the same pill for its walk to the first stop (`plannedKmh`).
On the follow card its ⓘ says why under it; an opened option says it from the
start.
The pace is only said: whether the ride is caught is judged at the hurrying
speed set, as above. On a ride the card warns ahead that the change will need it, with
"Find another way". A missed ride says the journey no longer works, with
"Search again". Either search asks for the same destination from on board the
vehicle ridden, sending only its id, or else from where you are, sent only on
that tap. It runs on its own, and the journey stays followed until another
option is followed. Waiting at the stop, where the vehicle is in sight, nothing
new is said - a ride already missed stays missed, the one there being a later
one. Nor is anything said while the vehicle ridden is not known.

A followed journey is kept on the device, with the destination, how far along
it was and the catalog's ETag, and is picked up again after a reload or a
restart (`web/src/lib/followed.ts`, `mobile/lib/src/followed.dart`). It goes
when it is ended, arrived or replaced, on another catalog, whose stop and route
positions it would misread, and 2 h past its arrival (chosen, not derived). On
the phone, a catalog renewed while the app runs drops it too.

By default it follows only while the app is on screen. The app has a setting,
off until turned on, to go on with the screen off: on Android a foreground
service keeps the location updates running behind an ongoing notification that
repeats the card, on iOS the location updates run in the background, and both
sound an alert once when it is time to get off, when the stop is passed, when
the next ride is caught only by hurrying or will be missed, and on arrival. Neither asks for background location: the updates were started while
the app was open, which the while-in-use grant covers. A browser cannot locate
with the page hidden, so the web card offers only to keep the screen on
(the Screen Wake Lock API) for as long as the journey is followed. The web
map's dot, the follower and every ask for where you are share one position
watch (`web/src/lib/position.ts`). A browser already watching may not answer a
second watch or ask until the device moves, so whoever comes later is handed
the last fix - as the app's one `Here` does.

One palette, two clients. `web/src/app.css` declares five colours, two radii and
one shadow in a Tailwind `@theme` block, and `mobile/lib/src/theme.dart` repeats
the same values; two of the colours, the near-black plate and the sky accent,
are the two colours in `web/public/icon.svg`, so both apps are the colour of
their own icon. Above that sit the utilities everything is built from - `panel`,
`bar`, `fab`, `inset-panel`, `btn`, `btn-quiet`, `field`, `field-bar` - and each
is translucent, blurred, a hairline ring and a soft shadow rather than a border,
because the map underneath is the context. The app's `Floating` is the same 80%
panel over a blur of the map behind it. A dialog dims the page and, on the web,
blurs it. Nothing outside `app.css` names a `slate-*` shade for a surface.
Whatever looks like one control is one target to its edge: a bar's inset is its
buttons' own padding, with the highlight on a span inside (the tab bar), and a
bare icon gets padding taken back by a negative margin (`-m-2 p-2`) rather than
a hit area the size of its glyph.

Nothing is docked to an edge. The map is the whole window in both clients and
every piece of chrome floats over it: a search bar and a menu at the top, the
tab pill at the bottom where a thumb is, round buttons for locate and
zoom (on the web only from the `sm` width up, since below it the cards span the
window and would cover them), and cards that rise off the bottom rather than out of it. That is why the
web layout is one `relative` box of absolutely positioned pieces instead of a
column, and why the phone's `Scaffold` has neither an `appBar` nor a
`bottomNavigationBar`: `floatingTop` and `floatingBottom` in `theme.dart` are
what anything scrollable uses to clear the two floating bars.

What goes where is decided by what a control does, not by how often it is
wanted. Which routes are tracked is the Lines tab's. Layers change
what the map draws - the route lines, the traffic, the basemap - and live in one
sheet behind a layers button, whose icon is lit while anything in it is on.
Everything belonging to the account rather than to the map is one tab, Mine. A
switch at its top shows one list at a time, so none hides another below it:
Stops, the pinned stops with what is due at each, dragged by a grip to reorder;
Places, the saved places; and Sets, the route sets (a tap makes one the watched
selection). In the app a row of any of them is renamed or removed from a menu on
a long press - a pinned stop is only unpinned, as it wears the stop's name; the
web gives each row its own buttons. The tab keeps the list it was left on.
Beside the switch, a button named with the username opens the account itself -
the language, the walking speeds, the server, the password, signing out - with
signing out below a rule so it is never the tap next to anything else. In the
app that is a sheet; on the web it takes the lists' place until it is pressed
again. A pinned stop is listed there once, with its arrivals.
Nothing that is a toggle and nothing that signs you out sits loose on the map.
That is `LayersSheet` and `AccountSheet` in `mobile/lib/src/sheets.dart` and
`mine_tab.dart`, and `LayersPanel.tsx`, `MinePanel.tsx` and
`AccountSettings.tsx` on the web.

The four tabs are Map, Lines, Journey and Mine - in Ukrainian Мапа, Лінії,
Поїздка and Моє, since "Маршрут" for a journey read as one of the "Маршрути", the
routes. Lines browses every route: All, Watching (the ticked ones) or Near me
(the routes of the stops within 500 m of the device's fix, asked for only when
picked; 500 m is chosen, not derived), the route sets to make one the watched
selection or save the ticks as one, the last five lines opened (kept on the
device), and the grid of route chips, whose body ticks a route and whose `›`
opens its line. Renaming and deleting a set is in Mine. An open line
uncovers the map and draws only that route, over a followed or planned journey,
beside a panel with a back button, a toggle between its two ways named by the
last stop, Watch, and its stops in order. On a phone that panel takes the lower
42% of the screen, so the line is framed in the larger part above it. Each stop shows when this route is
next due there, greyed while the vehicle is still finishing its previous trip,
and a vehicle is marked at the stop it reaches soonest. The order is the
server's: each shape line carries the stops of the longest trip on it
(docs/service.md). That way's stops are watched after the pins, the open stop
and a followed journey's, up to the server's cap of 64. That is `LinesPanel.tsx`
and `lib/lines.ts` on the web, `lines_tab.dart` and `lines.dart` on the phone.
On the phone the tab pill shows only the picked tab's label, as four labelled
tabs are wider than a phone. The web's `?tab=` names the open tab - `map`,
`lines`, `plan` or `mine` - and `?route=` the open line. A link from before,
`?tab=times` or `?tab=saved`, opens Mine, and `?tab=route` the Lines tab, on
the line when the link names one.

Changing the password is offered only where the service says it allows it
(`password_change` in `/api/me`), which it does not by default. Where offered, it
asks for the current one and the new one, and keeps the
form open with the service's reason while it refuses. Once taken, every other
device is signed out and so is this one's remember-me, so this device too signs
in again once its session lapses. That is `PasswordForm.tsx` on the web and
`mobile/lib/src/password_dialog.dart` in the app.

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

When the service says the vehicles have gone quiet - too few reporting for the
trips the timetable has under way, see
[the service](service.md#when-the-vehicles-go-quiet) - an amber banner with a
siren over the map is titled "Possibly an air raid alert", and below the title
says that few vehicles are reporting, so positions and arrival times may be
missing or off. It says "possibly":
a failing feed looks the same. Closing it hides it until the vehicles report
again and go quiet anew, and it is never shown while the socket is down, when
the service cannot say either way.

The language is Ukrainian, with English for a browser that asks for it;
`web/src/lib/i18n.ts` holds both dictionaries, MapLibre's own button labels
included, and the picker is in the account menu. Changing it reloads the page;
the phone app, which shares the same keys, switches without a restart.

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
a list of saved places in the Mine tab where a place can be renamed, though not
to another place's name, or dropped, a search that finds
addresses and shops as well as stop names, with matching saved places above
both, and lists the stops within 2 km of where you are (the web's ◎ in the search
bar, the app's search before anything is typed), traffic drawn over the streets
the model can see, following a journey as you travel it, and the banner that
warns when the vehicles go quiet.

The city writes most stops' codes into their names as well, "ТРЦ Кінг Кросс
(320)", and some stops' codes only there. Both stop cards take the code out of
the title and show it once, in brackets after the name, as the names write it:
the feed's zero padding ("0320") dropped, and the name's code taken over the
feed's where the two disagree. Everywhere else a name keeps its code, which is
what tells two stops of one name apart.

A place picked from the search or the Mine tab gets a card of its own and a
dot on the map, both gone once the card is closed or a stop or vehicle is picked
instead. The card names the place over its address, or says it is saved, keeps
it by its star, and plans the way there: the place becomes the destination under
its name, the start stays whatever it was or becomes where you are, and the
search runs as soon as both ends are set.

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
thereafter, which is what the offscreen badge canvases do in the browser. The
two maps count zoom differently - flutter_map's tiles are 256 px, MapLibre's
512 - so where the app starts drawing stops and place names, and how close it
comes in on a place, are the web's levels plus one (`webZoomOffset`): both do it
at the same ground scale.

It is built to be publishable on F-Droid, which is why it is Flutter and not
Expo: F-Droid builds from source and takes no proprietary SDK, so there is no
Play Services, no Firebase and no keyed map SDK anywhere in the tree. The
basemap is the same VersaTiles OpenStreetMap tiles, rendered on the device.
Its renderer (`vector_tile_renderer`) cannot read the styles' filters of the
form `["in", x, ["literal", [...]]]` and would leave out every layer that uses
one - all land use, parks and forests and most roads - so the app reads the
style through `basemap_style.dart`, which writes them as the equivalent `match`.
The one cost of that rule is paid by the locate-me button, which is a
hand-written channel - AOSP's `LocationManager` on Android, `CoreLocation` on
iOS - rather than the usual package, which brings Play Services with it; see
`mobile/README.md`. The app asks for the internet permission, and
for location on the first press of that button or of Follow; the fix never
leaves the phone.

The service needs one line for it: `app://commuterlviv` in `COMMUTERLVIV_ORIGINS`. The
app is not a web page and has no web origin, and that scheme is one no browser
will ever mint, so listing it cannot widen what a web page may do.
