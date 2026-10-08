# The live service

The same model, on wall time instead of a recording, is `commuterlviv/live/` behind
`python3 -m commuterlviv serve`. It polls the vehicle feed every five seconds, folds
each fix into the same tracks, steps the model on the same 60 s grid, and pushes
positions per poll and arrivals per epoch over a websocket. It shares the code
rather than resembling it: one epoch in the service is the same four calls
`replay._flush` makes offline, in the same order, so the numbers it serves are
the numbers the reports measured.

```sh
pip install -r requirements-live.txt
export COMMUTERLVIV_DATABASE_URL=postgresql://commuterlviv:...@127.0.0.1:5432/commuterlviv
export COMMUTERLVIV_ORIGINS=https://commuterlviv.r1a.nl,app://commuterlviv   # the web app, and the phone app
export COMMUTERLVIV_WEB_BASE=https://commuterlviv.r1a.nl     # optional; defaults to the first origin
export COMMUTERLVIV_VARIANT=profile                  # which predictor answers
python3 -m commuterlviv admin invite                 # a registration link, printed once
python3 -m commuterlviv serve
```

## Trips after this one

A vehicle's arrivals do not stop at the end of its trip. The trips the
timetable chains after it on the same vehicle (GTFS `block_id`) are predicted
too, and run to schedule from their first stop. Those rows are flagged
`planned`, and both clients show them in italics with a schedule mark. This is
what fills a start stop such as Аквапарк (519) for tram 3, where the vehicle
about to leave is still reported on the trip it just finished.

When the next trip leaves depends on the route and the terminus
(`commuterlviv/layover.py`). Never sooner than 120 s after the vehicle gets in,
and never before it can be there. Past that, trams and trolleybuses that get in
early mostly wait for the timetable - on most lines 85-90% leave within a
minute of it - but bus routes differ widely, and on half of them at most one
in five waits: the rest set off minutes, up to half an hour, ahead of it. So
each route keeps its last 50 early turnarounds at each terminus, each one
whether it left within a minute of the timetable and how far ahead of it it
left. Where at least 10 are kept and fewer than half of them waited, a vehicle
in early leaves as far ahead of the timetable as the upper quartile of those
that left after now - so one still in after all but two of them is taken to be
waiting for the timetable after all. On any other route it leaves on the
timetable, and a vehicle in late leaves 120 s after it got there. Asked every
minute of every early stand on the last 3 of the 14 days of recording to
2026-10-07, this took the departure's mean error from 10.34 to 6.48 minutes,
and the share foretold over two minutes after the vehicle had actually gone
from 50% to 16%. The turnarounds are kept with the model across restarts.

## The journey planner

`GET /api/plan?from=lat,lon&to=lat,lon` answers the door-to-door question:
walk, ride, maybe change, walk, ranked by arrival, with the whole walk offered
as one of the options. It is a profile connection scan (Dibbelt, Pajor,
Strasser, Wagner 2013) over the GTFS timetable, up to three rides so at most
two changes, with footpaths from an OpenStreetMap walking graph rather than
straight lines. There is no hardcoded radius for which stops count as nearby:
the bound is the time to walk the whole way, because a walk longer than that
can never be part of a better journey. A search takes about 0.5 s.

Walks climb. Every node of the walking graph carries its height, from the
Terrarium elevation tiles at zoom 13, and an edge's time is its length at
`SPEED` (1.25 m/s, 4.5 km/h, on the level) divided by Tobler's hiking function
of its slope, `exp(-3.5 * (|s + 0.05| - 0.05))`. So a gentle way down (5%) is
the fastest, and climbing is slower than descending the same slope. Slopes are
clipped to ±30% (`STEEPEST`). Rynok to the High Castle is 16.2 minutes on the
level, 19.8 up and 16.1 down. `&speed=<km/h>`, from 0.5 to 8, is how fast
this somebody walks on the level; the low end is for a walking frame or a
manual wheelchair at its slowest. Every walk in the search and on the map is
scaled by it, which costs about a millisecond. The walk caps below
(`TRANSFER_CAP`, `WALK_CAPS`) are distances in disguise: seconds at `SPEED`,
scaled by the same pace, so a slower walker is offered the same stops, each
further away in time. Both clients keep a usual speed on the
device (the account menu) and step it per search beside the departure time.

Walks are Dijkstra on that graph, scipy's (`scipy.sparse.csgraph.dijkstra`),
about ten times faster than one in Python. A point steps onto the graph
at the nearest point of the nearest footpath edge with a node within 150 m
(`Walk.attach`), and the search starts from both ends of that edge, each with
the walk to it already spent. Only edges on the largest connected piece of the
graph count: OpenStreetMap has hundreds of small pieces drawn apart from the
streets - a plaza, a platform, a courtyard - and a point or a stop stepping onto
one could walk nowhere. In Lviv's graph 4286 of 239922 nodes, and 17 of the 1071
stops' nearest edges, are on such pieces. Joining the point to every node in reach instead
would let a walk cut straight across a block to any of them. Two points on the
same edge are also joined along it, which the graph alone cannot see. The walk from the origin that finds
the whole walk also gives the walks to the stops near the origin, so a search
walks twice - from each end - in about 50 ms.

A tracked vehicle enters the search as an ordinary one-trip pattern built from
its own predictions, so where the model has something to say it outranks the
schedule automatically, and past the model's 45-minute horizon there simply are
no live trips left and the timetable takes over with no rule needed. Every ride
leg carries `live: true` or `false`, and both clients label it, because
somebody deciding whether to run for a bus deserves to know which of the two
they are reading. How much accuracy is lost at the far end of that horizon is
still unmeasured - it needs the VPS recording.

A tracked vehicle stands in for the scheduled trips on its route at each stop
up to the last time it calls there, so the timetable is only suppressed that
far. Later scheduled departures stay, since no vehicle is tracked on them yet.
A vehicle whose predictions run into the horizon is carried on to the end of its
line at the timetable's running times (`_run_on`), or a rider boarding it now
could not be taken past the 45th minute.

Every ride also carries a `confidence`, which is what the schedule is worth on
that route right now. `live` is a vehicle being tracked. `terminus` is a
tracked vehicle boarded on a trip after the one it is on, so its departure is
the estimate of [trips after this one](#trips-after-this-one). `schedule` is the
timetable on a route that is running. `quiet` is the timetable on a route the
schedule wanted at least twice in the last hour and nothing has been seen on
since - a line the city is not running today, which the timetable alone will
happily promise you a bus from. A `quiet` ride is held back unless it is the
only ride on offer, in which case it is returned and flagged: an unreliable bus
is worth knowing about, an invented one is not.

A ride also carries its `stops`: the catalog stops it calls at after boarding
and before getting off, in order, read off the same pattern its line is drawn
along (or the tracked vehicle's arrivals when no one pattern covers it), and
empty for a ride to the very next stop. The journey follower says to get ready
once the last of them is reached. A ride neither of those covers, a report's
stored journeys and an older service have no `stops`.

Every ride also carries its `backups`, `[{rides: [{route, dep, arr, a, b,
live, planned}, ...], arr, walk}, ...]`: the other ways to the door from the
stop it is boarded at, leaving after the chosen departure and reaching the door
at most half an hour after the journey arrives (`BACKUP_WINDOW`). `rides` is how
a way gets there, the first leaving from the stop, `arr` is when it reaches the
door and `walk` the seconds it spends on foot. A ride `planned` is on a vehicle
the journey itself rides further along: such a way catches the plan up after a
missed bus, but does nothing for a bus that does not come. Each sequence of
routes counts once, at its soonest run. So a route that parts from the chosen
one short of the door counts, and so does one that needs a change on the way.
The next run of the chosen route counts; the chosen departure does not. A way
that another one beats - leaving no sooner, reaching the door no later, in no
more rides, walking no more and riding no more of the journey's own vehicles -
is left out, since nobody changes twice to arrive with the bus they could have
waited for. So is a way that changes onto a vehicle which, before the way gets
off it, also calls at a stop where the way boarded, or at one a short walk
(within the shortest walk cap) beside it, no sooner than the way left there and
walked over. 53 then 16 onto a 16 that passes Угорська (439) after the 53 left
it is only that 16, waited for, with a change added. So is 53 out to Сквер
Думанського (421) and a 53 back that passes Угорська (438), across the street.
Tracked vehicles ride at their predictions, quiet routes do not
ride at all, and a scheduled departure a tracked vehicle is running is not
boarded.

Options and backups come from the same scan (`_Profile`), so a backup is
never a way the search itself would not take: up to `ROUNDS` rides, the minute
every change allows (`CHANGE`), and every walk - to the door and between stops
- under the same caps (`WALK_CAPS`, below). The scan runs backwards from the
door over every hop of every trip between now and the latest arrival that
counts: the whole walk, or `LONGEST_WALK` (4 h) when there is none, plus
`BACKUP_WINDOW`. Each hop learns the earliest door arrival from riding it in at
most 1, 2 and 3 rides under each walking cap, and each stop keeps the
departures worth boarding there. The options are read at the stops the origin
walks to, at the time the walk gets there; the backups at the stop each ride
boards. Before the scan, the hops are cut to a corridor (`_corridor`): those
leaving a stop no sooner than it can be reached from the origin, and reaching
one from which the door is still reachable in time. That keeps about a fifth of
them. Quiet routes are left out of the scan; it runs a second time with them
only when no option rides without them.

A backup that rides exactly what one of the listed options rides carries that
option's index in the server's list (`option`, -1 otherwise), and both clients
tag it "Option N" by where that option sits in their own order. That is how a
way listed on its own is also visible as another way behind a ride.

The journey's `backup` is the fewest any of its rides has, not counting ways
that ride the journey's own vehicles. Missing the bus stings less when another
way stands behind it, so a journey every leg of which has one outranks a
fragile one. The clients show the backups in a dialog opened from the option's
backup count: under each ride's stop the planned way comes first, then the
backups, each as its departure, its routes in order - a planned one outlined -
where it changes and when it reaches the door. A stop shows four at first
(`shortlist`): the best by the chosen preset, then the best by each other
preset, so a way is there should the thing the preset favours be what fails,
then the next best by the preset. They are listed in the order they leave,
which is the order they are needed at the stop; the rest are a tap away.

A tap on a way draws it. The planned way is the option itself, and a backup
that is also an option is that option. Any other backup is asked for with
`GET /api/backup?report=ID&option=I&leg=L&backup=N`: the search the `report`
id holds, its option `I` with backup `N` of its leg `L` taken in place of the
rest of the journey (all counted from 0 as sent, walks among the legs), built as `/api/plan` builds an option, with
the walks, shapes and `stops`, and its rides before that leg keeping their
backups. The clients list it as an option of its own, after the others. It
answers 404 when the search is no longer held or has no such backup, 400 for an
index that is not a whole number, 409 when the city was renewed since the
search, and 503 while the planner is busy. The rides a built option shares with
the option it came from are the only ones with backups, so the clients ask for
those under that option's index.

Every leg also carries `pts`, `[[lat, lon], ...]`, which is where it goes on the
map: a walk follows the footpath graph (`walk.path`), and a ride is its shape cut
between the stop it is boarded at and the stop it is left at. Both are simplified
to 4 m. The clients draw the option you tap - walks dotted, rides solid in the
route's colour, one pill of times per stop where getting off and getting on
share the reading - and wipe it, with the A and B marks, when you leave the
planner. The first tap on an option only picks it; its stops and routes open
their own views once it is picked.

The options are ranked by a front over arrival time, backups, number of
changes and seconds spent walking, so a slower journey every leg of which has
another way behind it survives alongside the fastest hanging on one vehicle,
and every option that does not beat simply walking the
way is dropped. Keeping only the earliest arrival would lose a ride from the
door to a slightly faster one behind a 12-minute walk, and it would never
reach the front. So the scan also keeps, per hop, the earliest arrival with
every walk capped at 10 and at 5 minutes (`WALK_CAPS`), as slots of its own
in the same pass.

A ride a minute or two before an option's that arrives a minute or two after it
is an option too, though the other beats it: at the stop, whichever comes first
is the one to take. So each option may bring one near tie (`_Profile.near`): a
way whose first ride leaves at most 5 minutes before the option's and which
reaches the door at most 5 minutes after it (`NEAR_TIE`, chosen, not derived),
the soonest at the door counting the minutes walked. It rides no vehicle an
option or another near tie rides, since that is no other way should the vehicle
be late, and it is not a bus waited for with rides added, as for backups. А10
at 13:55 to the door at 14:13 is listed beside Тр38 at 13:56 to the door at
14:11 this way.

The server's order is the fastest first. Both clients re-sort the same options
by a preset - fastest, less walking, fewer changes, most backups - picked from
a sort icon beside the search and remembered on the device; the whole walk goes last
under the last two. Under those two, a tie is settled by arrival plus the
minutes walked, so a ride from the door beats one a few minutes earlier behind
a long walk. `&at=<unix seconds>` plans a trip that starts later instead of
now, up to 30 days ahead (`PLAN_AHEAD_DAYS`); past that the city has usually
changed its timetable. Each day is planned on the trips its services run
(`calendar.txt`, with `calendar_dates.txt` exceptions winning), so a Sunday
does not get a weekday timetable; the day before's trips running past midnight
and the day after's are part of it (`Pattern.running`, `Timetable.on`). A later
departure still rides the vehicles being tracked - only their
arrivals that lie ahead of it are kept - so nothing is thrown away at some
cutoff; past the model's 45 minute horizon there are none left and the timetable
takes over on its own.

### Reporting a search

A wrong answer usually cannot be seen again afterwards: it ran on predictions
that are gone a minute later. So every search is held in memory for 30 minutes
(`reports.KEEP`, at most 300 at once) with the arrivals it ran on, and its
answer carries a `report` id. Nothing is written unless the one who searched
taps "Something looks wrong? Report it" under the options, which sends
`POST /api/report` with `{"id", "note"}` - the note is optional, up to 1000
characters. That writes one compressed file to `data/reports/`: the request,
those arrivals, the catalog's stop and route ids they are indexed by, the answer
as sent, the version, the account's id and the note. An id is good for one
report, and only the account that searched can use it, for the report and for
`/api/backup`; one that has expired is a 404. Past 200 files (`reports.FILES`)
new reports are a 507 until some are read and deleted.

`python -m commuterlviv report FILE` prints the answer as it was sent and then
the one the code and timetable at hand give for the same request and arrivals,
so a fix can be checked against the case that prompted it. When the feed has
changed since, it says so: stop and trip numbering may then no longer match.

## Traffic

`GET /api/traffic/streets` and `GET /api/traffic` are the same numbers the
model uses for its ETAs, drawn as a map: per 100 m of track, the ratio of how
long vehicles are actually taking to how long the timetable expects. A stretch
too little has crossed lately comes back as `null` and is not drawn - the model
would happily hand back the corridor's number there, which is a fair ETA and a
meaningless traffic reading.

The numbers are pooled before they are drawn. A unit belongs to one route's
shape, so a street ten routes run down carries ten units, each with its own
number and its own idea of where the kerb is; drawn as they are, that is ten
near-parallel lines crossing each other. They are pooled by where they lie:
shapes are laid down most-run first, and a 100 m cell of a later shape that runs
on top of an already drawn piece, within `MATCH` metres and heading the same
way, adds its unit to that piece instead of drawing its own. Each piece is drawn
along its shape's own vertices, so it follows the street through a bend rather
than cutting a chord across it. An earlier version pooled on `Shape.corridor`,
a 120 m box crossed on one of eight headings, and drew each box as one straight
line - which is what cut the corners on Зелена and stacked lines along Княгині
Ольги. The one split kept is tram against road: a tram on its own track is not
in the traffic the buses are in, while a trolleybus is on the road with them and
is pooled with them. The geometry is fixed until the feed changes and
cached by ETag; the ratios come separately, in the same order, and are built and
serialised once every 30 s rather than per request.

Two hundred metres at either end of every shape are left out entirely. A vehicle
at a terminus crawls in, parks, and crawls out, and the crawling is rolling time
over cells whose timetabled pace is short, so the ratio there is high on every
route in the city - which is a layover and not traffic. That drops 1087 of the
26,712 units the model learns. Only that shape's own units go: a route running
past another's terminus still pools its own view of the street.

Neither client draws the stretches one at a time. The phone projects them once,
at zoom 18, and gathers them into one path per colour, so a frame is a couple of
dozen `drawPath` calls under a single transform and panning re-projects nothing;
the browser hands maplibre one GeoJSON source and replaces its data only when
new numbers arrive. Both push each line to the right of its own travel, so the
two directions of a street sit side by side rather than one hiding the other.

## Search

`GET /api/search?q=` finds addresses and places by name, which the catalog
cannot. It asks two sources. The first is a local index, `data/lviv-search.sqlite`,
built by osm-mapidx (https://github.com/rhusiev/osm-mapidx) with
`python -m mapidx.cli build ukraine-latest.osm.pbf --region lviv`; its search
code is vendored as `commuterlviv/mapidx/`. It forgives typos and Latin
transliteration, and leads for queries without a digit. The second is Photon
over OpenStreetMap, biased to the city and clamped to it, which leads when the
query has a digit, since house numbers are what it is best at. The same name
within 100 m is kept once. Answers are cached for a day.
The index is not in the image. `.github/workflows/places.yml` rebuilds it from
OpenStreetMap on the 3rd of every month and publishes it on this repository's
`places` release, because the build streams the whole Ukraine extract and peaks
near 5 GB. It runs osm-mapidx's builder at a pinned commit, the one the vendored
search was copied from, so the two only ever move together. The service
downloads it from `COMMUTERLVIV_PLACES_URL` on a start without one, then at the
nightly check once it is 30 days old. A download is kept only if it opens and
finds Lviv, and is swapped in with a rename; each search opens the file anew, so
no restart is needed. A failed one keeps the held index and is tried again the
next night. Without any index the local half is simply absent.
`COMMUTERLVIV_PHOTON_URL` points Photon at a self-hosted instance, and emptying
it leaves the local index alone; with neither, searching falls back to stop
names. Stop names themselves are matched in the client by word prefix, in any
order, with й/и, ї/і and apostrophes folded and one typo allowed in a word of
four letters or more (`match.dart`, `match.ts`).

## The planner's caches

The planner needs two caches that are built once and are not in the image:

```sh
python3 -m commuterlviv walk         # data/walk.npz, the OSM footpath graph
python3 -m commuterlviv plan --build # data/transfers.npz, stop-to-stop on foot
```

`walk` also fetches the height of every node; it is asked for again on a graph
that has none, so an older `walk.npz` gains it in place. `walk.npz` is pure
OpenStreetMap plus elevation and can be copied between hosts; `transfers.npz`
indexes stops by the catalog it was built against and must be rebuilt wherever
`network.pkl` differs. It also records what it was built from: the walking model
(`model`, such as `1.25 m/s, Tobler slopes`), a digest of the footpath graph and of
which part of it is walked on (`graph`) and one of the catalog's stops (`stops`). The service rebuilds it when
any of the three is not what it holds - about 8 s, written beside the old file
and swapped in. A file from before the digests has none, so it is rebuilt once. Without them the service still starts, logs why, and
`/api/plan` answers 503 - the map and the arrivals do not depend on it.

## Route shapes

`GET /api/shapes` is where a route physically goes: per route, the polylines its
trips follow, each marked with the feed direction it runs. Direction is drawn by
the clients, not served - a run both ways gets two tracks of chevrons, one per
side, spaced on screen rather than on the ground, which is why nothing here has
to be respaced per zoom. 245 KB, 33 KB gzipped, one ETag per feed, and both clients ask for it
only the first time something wants to draw a line - tapping a vehicle's badge
to see its route, or the button that puts the whole network on the map. Nobody
who opens neither pays for it.

## Keeping the city current

The feed and the footpaths change under a running service, and it follows them
without a restart (`commuterlviv/live/refresh.py`):

1. Every night at 03:30 Kyiv time (`CHECK_AT`), after the last tram and before
   the first, it wakes up. Nobody is riding, so nobody notices what follows.
2. If `walk.npz` is over 30 days old (`WALK_EVERY`), the footpaths are fetched
   from Overpass again, heights and all, into `walk.next.npz`. A graph with
   under 90% of the old one's nodes is taken as a broken answer and dropped;
   otherwise it replaces the old file.
3. The static feed is fetched again (`gtfs.refetch`). A body that is not a zip
   with `routes.txt`, `trips.txt` and `stop_times.txt` in it is refused, and
   the held file stays.
4. The feed and `overrides.toml` are hashed (`network.source`) and compared
   with what the service is serving. The same hash and new footpaths rebuild
   only the planner, which is then swapped in. The same hash and nothing else
   new is the end of the night.
5. A new hash builds the whole city beside the old one, in worker threads:
   the network, the live model, the shapes and street JSON and the planner.
   Meanwhile the old city keeps serving. A new feed with under half the old
   routes (`SHRINK`) is taken as broken.
6. The new model takes over what the old one learned. The old model is copied
   under the lock (`snapshot.export`) and read into the new one
   (`snapshot.restore`) for every shape the feed left alone - same id, same
   number of cells, length within 1% - and every corridor both cities have.
   It is then warmed on the recording since that copy, which is the last
   minute or so. A shape the feed changed starts from the timetable.
7. The new city is swapped in under the model's lock, polled once and stepped
   one epoch so it is not published empty. The planner is swapped with it, and
   a plan asked for in the instant between the two answers 503 rather than
   mixing one city's stops with the other's arrivals.
8. Every socket is closed with code 1012 ("service restart"), and a socket
   that was mid-push when the swap landed closes before it sends a frame of the
   new city under the old indexes. The clients reconnect within a second. The
   first frame on a socket is `hello`, which carries `catalog`, the catalog's
   ETag, and a client subscribes only after reading it: its route filters are
   indexes into the catalog it holds, so they would mean other routes in
   another city. A client holding another catalog knows every route and stop
   index it has is stale. The web app reloads itself, keeping the view in the
   URL by feed id, and says the routes were updated. The phone fetches the
   catalog, carries the selected routes, pins and open route over by feed id,
   closes open sheets and says the same; if the fetch fails it tries again
   every 5 s.

The catalog, shapes and streets are served `no-cache` with an ETag, so a client
asking after a renew always revalidates and never gets the old city from its
HTTP cache.

Any step that fails leaves the old city serving, the new feed is put back to
the one served (`gtfs.restore`) so a restart does not pick it up either, and the
next night tries again. The cost of a swap is about 15 s of CPU in the background and, while it
lasts, a second copy of the city in memory. The cost to a rider is one reconnect
and, on the web, one reload.

The planner is also missing while it is first built (see above). Then
`/api/plan` answers 503 with `"preparing": true`, and both clients say the
planner is getting ready, rather than that there is none.

## The model across restarts

What the model has learned is kept in `data/model.npz` (`commuterlviv/snapshot.py`).
The service writes it every 10 minutes (`SAVE_EVERY`) and on shutdown, and reads
it on start. The `profile` variant's hour-of-day means have a one-week
half-life, so without it every restart would throw away days of learning that
two hours of recording cannot replay.

1. On start the service reads the snapshot into a fresh model. Its indexes are
   positions in one build of the feed, so it carries what each meant - shape
   id, cell count and length per unit, the corridor key per corridor - and only
   what still matches is read back.
2. It then replays the recording from the later of the snapshot's time and two
   hours ago (`WARM_HOURS`), so the minutes between the last save and the
   restart are learned again.
3. Every weight carries the time it was earned and decays from that stamp, so
   an old snapshot needs no expiry: it fades back to the timetable on its own.

A missing or unreadable snapshot is not an error - the model starts from the
timetable, as it did before the file existed, and the log says so. The
snapshot is about 35 MB, and only the per-cell online models
(`snapshot.supported`) have one. It also carries each route's recent early
turnarounds at its termini ([trips after this one](#trips-after-this-one)),
which a snapshot from before they were kept simply lacks: they are then
learned again as vehicles come in.

## Accounts and registration

Accounts are required for everything except `/api/health`, for two reasons,
neither of them capacity. They carry a person's named route sets and pinned
stops between their devices, both stored as feed ids so that a rebuilt catalog
cannot quietly move them. And a watching client costs only bytes - the model runs once for the
whole city - so what the gate protects is not the CPU but the output: a tracked,
smoothed, city-wide vehicle history, handed over at 228 B/s to anyone who opens
the socket. Passwords are argon2id, sessions are opaque rows in Postgres behind
a `__Host-` cookie, and remember-me is series+token rotated on every use, where
a spent token coming back is treated as theft. Migrations apply themselves at
boot and there is no down direction. The socket is not signed in once and
trusted forever: it re-asks about its session every minute and closes with 4401
when it has gone, it takes five messages a second with a burst of sixty, and it
hangs up on a client that spends 500 messages past that.

Registration is `COMMUTERLVIV_REGISTRATION=open|code|closed`, `code` by default.
Under `code` there is no way in without a link an admin minted: `admin invite`
prints `<web base>/join/<code>` once, the web app posts it to
`/api/register/{code}`, and only the code's SHA-256 is stored - so a lost link
is gone rather than recoverable. Under `open` the same request without a code,
to `/api/register`, is accepted. Both clients read the setting from
`/api/health` before anyone is signed in and show what it allows: an invite
field, a sign-up button, or neither. It is on the public endpoint because there
is no one to ask when the question is asked, and because it is not a secret -
whether a service takes new accounts is answered by trying.
