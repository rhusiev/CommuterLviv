# The next eight things

Each item says what is wrong now, and what to build. Order is the order they
land in; the planner items share machinery, so they come as one block.

## 1. Favourites you can actually manage

Now: `/api/places` is a whole-list write, and the only way to create one is a
long-press on the map. Nothing lists them, renames them or deletes them. Pinned
stops (`sets.pins`) have the same problem.

Build: one Saved screen in both clients, over the existing endpoint - list
places and pinned stops, rename, delete, reorder by drag, and tap to show on the
map. Renaming is a delete plus a save, because the name is the identity
server-side; the client does both in one write of the whole list, so it stays
atomic.

## 2. Search that finds places, not just stops

Now: search filters the catalog's stop names in the client. An address or a shop
returns nothing.

Build: **Photon** (`photon.komoot.io`, OpenStreetMap, built for
type-as-you-go), proxied through `/api/geocode?q=&lat=&lon=`. Photon is chosen
over Nominatim because it indexes every named OSM object, not just addresses,
and answers prefixes - which is the exact complaint about OSM search being poor
outside house numbers. The proxy:

- biases to Lviv with `lat`/`lon` and clamps results to the network bbox
- caches by normalised query for a day, so repeat typing costs nothing
- rate-limits per session, and can be pointed at a self-hosted Photon later by
  one setting, since the public instance asks that heavy users run their own

Results merge into the existing list under a heading, stops first. Every row
gets a save-as-favourite action, which is item 1's write.

## 3. Every option that beats walking

Now: `journeys()` keeps 5, ranked by arrival then rides, dropping anything
dominated. A slower ride with one change fewer, or one leaving later so you need
not run, is thrown away even when it beats walking.

Build: keep every journey that arrives before the all-walking option, and rank
by a Pareto front over (arrival, rides, walking seconds) rather than
(arrival, rides). Raise `keep` to 8 and let the front decide. The all-walking
option stays in the list as the baseline it already is.

## 4. Walk between rides - confirmed, and then honest about it

Answer to the question: yes. `transfers.near()` relaxes a footpath from every
stop marked in a round, so walk -> ride -> **walk** -> ride -> walk is already
reachable, capped at `TRANSFER_CAP`. What is missing is that `ROUNDS` bounds the
rides and the cap bounds each footpath, and neither is surfaced.

Build: nothing in the search; show the transfer walk as its own leg with its
distance in both clients, which today collapses into the ride.

## 5. No more phantom buses

Now: `_scan` falls back to the timetable for any (stop, route) no tracked
vehicle covers. If the city runs nothing on a line all evening, the schedule
still promises a bus.

Build: a per-route liveness score in the live state - seconds since any vehicle
was last tracked on that route, and how many ran in the last hour against how
many the schedule wanted. A scheduled departure is then:

- used as-is when the route is running
- used but marked `confidence: "schedule"` when the route is quiet but young
- suppressed entirely when the route has been silent for longer than twice its
  headway and the schedule says several should have passed

The wire gains `live` per leg (it exists) plus `confidence`, and both clients
say so on the leg rather than hiding it. A suppressed route can still be
returned if it is the only option, flagged as such - an unreliable bus is worth
knowing about, a silent invented one is not.

## 6. Leaving at a time you choose

Now: `search()` passes `now = time.time()`.

Build: `?at=<unix>` on `/api/journeys`, passed to `journeys(..., now=at)`. A
future time has no live vehicles, so the answer is schedule-only and marked that
way by item 5's confidence field. Both clients get a time chip next to the
route-planner fields, defaulting to Now.

## 7. No walking to a stop to walk away from it

Now: `_unwind` returns the access walk, then a transfer walk, as two legs; a
journey can also board and alight with rides that save nothing.

Build: after unwinding, fold consecutive walk legs into one, and drop any
journey whose ride legs are all shorter than the walk that would replace them.
Both are a pass over the leg list, so they cost nothing in the search.

## 8. Traffic, and route direction

Traffic view: the pace model already holds a travel time per cell of every
shape, which is speed over a known length. A `/api/traffic` returns, per cell
with enough recent crossings, the current pace against that cell's own median,
as a colour ramp. Confidence gates it: fewer than N crossings in the window and
the cell is simply not drawn, which is why this is honest where a
whole-city-coloured map is not. Streets with no transit on them have no data and
stay grey - the view is what the trams and buses can see.

Direction: replace the arrow glyphs along the line with a dashed casing whose
dashes are chevrons pointing the way of travel, animated slowly on the selected
route only. A two-way stretch draws both offsets side by side instead of the
current shared arrow.
