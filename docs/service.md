# The live service

The same model, on wall time instead of a recording, is `commuterlviv/live/` behind
`python3 -m commuterlviv serve`. It polls the vehicle feed every five seconds, folds
each fix into the same tracks, steps the model on the same 60 s grid, and pushes
positions per poll and arrivals per epoch over a websocket. It shares the code
rather than resembling it: one epoch in the service is `replay.step`, the call
the offline replay makes for each of its epochs, so the numbers it serves are
the numbers the reports measured. That step feeds the model what the tracks
crossed, forgets vehicles gone quiet, refreshes the model, and forecasts: every
vehicle that reported within `replay.STALE` (120 s), is placed on its shape and
still has a stop ahead is timed, and every other vehicle that reported within
it and that the departure model saw get in at the end of its trip is noted
standing for its next one.
Only then does the service drop what the clients cannot show - a vehicle whose
route the catalog lacks - and add the trips each vehicle runs next
([trips after this one](#trips-after-this-one)). So a vehicle first seen
already standing at its last stop is timed by neither: it has no stop ahead,
and nothing saw when it got in.

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
in early leaves halfway between two estimates. One is as far ahead of the
timetable as the upper quartile of those that left after now - so one still in
after all but two of them is taken to be waiting for the timetable after all.
The other is as far ahead as the last vehicle in early there went. On any
other route it leaves on the timetable, and a vehicle in late leaves 120 s
after it got there.

That rule is the fallback. Every minute a vehicle stands in early, the service
also notes what the rule's two halves said, how long ago and how far ahead of
the timetable the route last left that terminus, the timetable's gap to it,
the hour, and how long the vehicle has stood, and a replay of the recording
notes the same (`replay.forecast`); once the vehicle leaves, each of
those minutes is labelled with how long was really left. A gradient-boosted
model (scikit-learn's `HistGradientBoostingRegressor`) is fitted on start,
every 6 hours (`FIT_EVERY`) and after a feed swap, in a worker thread, on
50 000 of the newest 500 000 such minutes - about 12 s of CPU - and once
20 000 are there it times every vehicle standing in early, all of them in one
call a minute of a few milliseconds. It foretells the 0.4 quantile rather than the median, which
keeps it as rarely late as the rule.
Asked every minute of every early stand on the last 3 of the 14 days of
recording to 2026-10-07, the timetable was out by 10.34 minutes on average,
the rule by 6.02 and the model by 5.14, and the share foretold over two
minutes after the vehicle had actually gone was 50%, 17% and 17%. The
turnarounds and the minutes of stands are kept with the model across restarts.

## What the feed says of a vehicle, and doubted arrivals

Besides where a vehicle is, the feed names it: `license_plate` carries a tram's
or trolleybus's fleet number and a bus's plate, and `label` reads `low_floor` or
`high_floor`. The service keeps both per vehicle (`Live.meta`). A vehicle the
feed calls low floor carries the `LOW_FLOOR` bit (4) in its frame's flags, and
its arrival rows `low_floor: true`. The word is taken only where it is said: on
2026-10-29 it named 10 of 71 trams and 28 of 63 trolleybuses low floor but one
bus in 484, so a vehicle without the bit is unknown, never high floor.
`/api/vehicle` adds `fleet`, `low_floor` and `seen`, the Unix second of its
last report.

An arrival is doubted, `doubt` on its row, when its vehicle has stood still
for over five minutes (`STUCK_S`) away from either end of its line (`ENDS_M`,
150 m, where standing is laying over) - the `STUCK` bit (8) - or when it has not
reported for `FRESH` (30 s), the `STALE` bit: `"stuck"` and `"silent"`. Both are
judged on the positions last published, so a stop's board and the map agree.

## Seconds to each stop, corrected

The pace model reads Lviv as faster than it is - over 2026-09-14..10-08 it
foretold arrivals 112 s early on average - and it knows nothing of a route's
habits, of the day of the week or of a vehicle running late. A second
gradient-boosted model (`commuterlviv/boost.py`) learns its misses and takes
them off:

1. Every 10 minutes (`SAMPLE_S`) the service notes, for 15% (`KEEP`) of the
   stops each vehicle is foretold to reach, what the model said with the
   timetable's seconds to the same stop, how late the vehicle runs, the
   metres and stops to go, its speed, the age of its fix, the hour, the
   weekday, the route and its type, and the model's seconds per timetabled
   second. With them go what the last minutes said (`commuterlviv/recent.py`):
   how far the stops the city passed in the last 30 minutes came off their
   first forecast inside 15 minutes, as the median of the log of real over
   foretold seconds, and how many there were; the vehicle's own metres per
   second over the last 5 minutes and the model's seconds per second for
   that stretch; and the metres to the vehicles ahead and behind on the same
   shape, the model's seconds to the one ahead and the age of its fix.
2. When the vehicle passes that stop, timed between fixes at most 120 s
   apart (`MAX_GAP_S`), each note is labelled with how many seconds later
   than the model it got there. A note whose stop is not passed within 2
   hours is dropped. The newest 500 000 labelled notes, about 6.5 days, are kept.
3. The fit loop fits the correction on them with the terminus model, once
   there are 20 000 (`NEED_ROWS`, about 6 hours of service). Every leaf of it
   holds at least 200 notes (`MIN_LEAF`, with an L2 penalty `L2` of 10): on a
   week of notes that changes nothing, and fitted on the first hours after a
   start it misses 153 s rather than 158 s against the model's 169 s.
4. Every epoch, every vehicle's seconds to every stop inside the horizon are
   corrected in one call of the model. Within a minute of a stop the model is
   better than the correction, so the correction is faded in from 60 s to
   180 s of the model's seconds (`FADE_FROM_S`, `FADE_S`), chosen, not derived.
   The seconds are kept from falling and from going below zero along the trip.
5. The corrected seconds are then brought forward by 4% of themselves
   (`EARLIER`), faded in the same way. The correction alone is as often early
   as late, and that made riders miss the vehicle: foretold over two minutes
   too late 14% of the time against the model's 8%. Brought forward, that is
   8% again, at 135 s rather than 127 s over the replay below. All of that
   is lost past 10 minutes out; under 10 minutes it is closer than without.
   3% was 132 s and 9%, 5% was 139 s and 7%.

Replaying the recording of 2026-09-28..10-07 through the service's own code,
fitted after each day and scored on the last three (1.5 million ETAs), the
correction without step 5 brought the mean miss from 178.5 to 127.1 s, from
237 to 161 s 20-45 minutes out and from 21.3 to 22.3 s under two minutes.
Without what the last minutes said it was 130.9 s, and 138.9 s at the 3% that
brings its misses to the model's. A fit takes about 50 s of CPU in a worker
thread every 6 hours. Correcting the morning peak's 7 600 stops takes about
0.12 s of CPU a minute, 0.05 s of it for what the last minutes said. The
500 000 notes take 46 MB.

## When the vehicles go quiet

During an air raid alert in Lviv the vehicles stop reporting where they are,
and the map empties while the buses still run. The feed itself failing looks
the same, so the service only says the vehicles have gone quiet and both
clients word it as a possibility: few vehicles are reporting, possibly an air
raid alert, positions and arrival times may be missing or off.

Every epoch the service counts the vehicles with a fix in the last 120 s
(`replay.STALE`) against the trips the planner's timetable has between leaving
their first stop and reaching their last (`commuterlviv/live/quiet.py`). Under
half of them reporting is quiet (`QUIET_SHARE`), but only while at least 50
trips are under way (`MIN_RUNNING`): at night the timetable has next to nothing
running, and an empty feed then means nothing. Until the planner is built
nothing is judged. On the recording of 2026-09-13..17 in 10-minute samples, a
vehicle reported for 0.83-1.2 of the trips under way in normal service, for
0.00-0.21 through four blackouts and 0.40-0.43 at their edges, and night had
fewer than 50 trips under way. Both thresholds are chosen in that gap, not
derived.

The `hello` frame carries `quiet`, and a `{"type": "quiet", "quiet": ...}` frame
follows each change. `/api/status` shows `quiet` and the count `reporting`.

A blackout also misleads the tracks. Through it many vehicles go on reporting
with fresh timestamps while their place, odometer and speed stop changing, then
the place jumps kilometres ahead while the odometer barely moves - see
[the filter](how-it-works.md#3-the-fix-is-folded-into-a-filter-not-used-directly)
for what the tracker does about that. A vehicle back from a silence longer
than 300 s (`track.GAP_RESET`) may have left its terminus, or been to the
depot and back, unseen, so no stand or departure is timed off it until it next
gets in (`Layovers.follow`). That drops 25 of 1052 departures replaying
2026-09-15 19:00-21:00 and almost none in normal service.

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
device (the account settings in the Mine tab) and step it per search beside the departure time.
`&hurry=<km/h>`, from 0.5 to 12 (`HURRY_KMH`, a brisk run, chosen, not
derived), is how fast they would walk to the first stop to catch a bus; see
hurry options below. Both clients keep it beside the usual speed, off until
set, and send it only then.

The graph holds the ways OpenStreetMap lets somebody walk (`WALKABLE`), and
every stop platform, whether it is tagged `highway=platform` or only by its
transit role (`railway=platform`, `public_transport=platform`). A platform is
where somebody waiting at a stop stands, and often the only way drawn on that
side of the street: without it, a point on the platform steps onto whatever is
nearest instead - in one reported search a car park's aisle, which joined the
streets 200 m away and made a stop 13 m off a 5-minute walk.

A road whose pavement is drawn as a way of its own - `sidewalk`, `sidewalk:both`,
`sidewalk:left` or `sidewalk:right` set to `separate` (`SIDEWALKS`) - is left out,
unless it says `foot=yes`, `permissive` or `designated`, as OSRM's foot profile
does. Otherwise the road is a footpath of the same length as the pavement beside
it, and a walk can cross the street anywhere along it: in one reported search it
walked 200 m down a three-lane carriageway and turned through the median. Tags
are fetched only for those roads (141 in Lviv on 2026-10-21, 234 of 241111
nodes); the rest of the city comes without tags, which would time Overpass out.
Most of Lviv's pavements are drawn without that tag on the road beside them, so
the rule fixes a street only once it is tagged in OpenStreetMap.

Walks are Dijkstra on that graph, scipy's (`scipy.sparse.csgraph.dijkstra`),
about ten times faster than one in Python. A point steps onto the graph
at the nearest point of the nearest footpath edge with a node within 150 m
(`Walk.attach`), and the search starts from both ends of that edge, each with
the walk to it already spent. A stop steps on the same way, from its pole
(`Walk.stands`), so somebody standing at a stop and the stop itself are on the
same edge; the nearest node instead can be across the road. Only edges on the
largest connected piece of the graph count: OpenStreetMap has hundreds of small
pieces drawn apart from the streets - a plaza, a platform, a courtyard - and a
point or a stop stepping onto one could walk nowhere. In Lviv's graph 4447 of
240985 nodes, and 24 of the 1071 stops' nearest edges, are on such pieces.
Joining the point to every node in reach instead would let a walk cut straight
across a block to any of them. Two points on the same edge are also joined
along it, which the graph alone cannot see. The walk from the origin that finds
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

`veh=<id>` in place of `from` searches from on board that tracked vehicle, so
only its id leaves the device. It is searched as getting off at the vehicle's
next stop when the vehicle gets there, the stops a short walk from that one
included, and every journey found is then ridden there on it (`plan.Aboard`,
`_on`). Staying on is one ride from now. Getting off for another vehicle is a
change like any other, so a departure sooner after getting off than the change
needs (`change_slack`, below) is dropped. When the door is in walking reach of the next stop, one more
option gets off there and walks. The ride there starts at the stop before the
next one, taken from a pattern of the route that runs the next two predicted
stops one after the other. A vehicle standing at its first stop has none, and
neither does one whose next two stops no pattern runs in a row - across a
layover, say. Its journeys then start at the next stop instead. An option that
starts on board carries `aboard: true`, and the clients follow it as a ride
already under way. That ride needs no backups, so it is left out of the ranking's
count of them. A ride slower than walking is not dropped here, since it is
already being ridden. A vehicle the planner no longer sees running gets no
options. On board the journey leaves now, so `at` is refused with `veh`.

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
never a way the search itself would not take: up to `ROUNDS` rides, the slack
every change needs (`change_slack`), and every walk - to the door and between stops
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

A change needs slack over and above the walk between the two stops, and more the
further ahead it is (`change_slack`): 60 s for one up to a minute away, read in
between the points of `CHANGE_AHEAD`/`CHANGE_SLACK`, up to 300 s from about 37
min out. Both rides' times are forecasts, and the forecasts miss by more the
further out they are. The figures come from a replay of 2026-09-16..21 on a
model warmed on the 7 days before and refitted after each day: every 10 min of
it, tracked vehicles reaching a stop were paired with tracked vehicles of
another route leaving it or a stop within a 5 min walk, and a change counted as
broken when the true crossings left less than the walk. Each point is the slack
from which at most 15% of changes broke (a chosen target, not a derived one), in
a band of 0-2, 2-5, 5-10, 10-15, 15-20, 20-30 and 30-45 min ahead, placed at the
band's middle. The flat 60 s it replaces broke 11% of changes 0-2 min ahead, 26%
5-10 min and 38% 30-45 min, and a broken change cost a median 13-14 min to the
next vehicle of the route. The figures moved by at most 30 s from one day to the
next. Searched on the timetable alone, the soonest arrival came 3.1 min later on
average than with the flat 60 s, and later at all in 43% of searches; a target
of 10% would have cost 4.1 min and 5% 6.0 min. Changes onto a timetabled
departure, or onto the next trip of a tracked vehicle still at its terminus,
were not measured; they take the same slack.

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
share the reading, centred on the stop or, on a saved place, standing above it
clear of the place's name, and no times for a walk under a minute, which somebody
already at the stop would read as walking from 18:35 to 18:35 - and wipe it,
with the A and B marks, when you leave the planner. The first tap on an option only picks it; its stops and routes open
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

A bus that leaves the first stop just before somebody walking there arrives is
an option too, flagged `hurry: true` (`_Profile.hurrying`): one caught at the
`hurry` pace, or a tracked vehicle missed by at most 10 s (`GRACE`, chosen,
not derived), which a driver waits for when waved to. Only a tracked vehicle
is known to the second, so a timetabled one is never caught by waving. The
options are read once more at the stops as reached that much sooner, from the
same scan; `journeys` takes the pace as `hurry`, the share of the usual walk's
time hurrying takes. Hurrying is the last criterion of the front, so a hurry
option never pushes out a calm one, and only the walk to the first stop is
hurried. That walk is sent at the hurried pace, ending as the bus leaves when
only waving catches it. A backup of a hurry option's first ride walks at the
usual pace. From [49.8187, 24.0310] at 20:09 at 5.5 km/h, westbound А16 left
Енергетична 7 s before the walk got there and reached the door at 20:33; the
calm option, А16 the other way and a change to А41, at 20:43.

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
transliteration, and holds each street once, but no house numbers. The second is
Photon over OpenStreetMap, biased to the city, which has both. A query with a
digit is a house address, so Photon leads it. Otherwise the index's places with
the query in their own name lead, streets first, then Photon's, then the index's
places only on or near something of that name: "проспект Шевченка" is the avenue
before the cafés on it, and "зелена" is Зелена вулиця before Зелена Сливка.
Photon answers a street once per stretch of it in OpenStreetMap, so its street
of one name in one district is kept once, and none is kept where the index found
a street of that name. Both are clamped to the box the map
frames can place a vehicle in (`wire.py`), widened by the footpaths' reach past
the stops (`walk.MARGIN`), which `/api/plan` also refuses points outside of:
past it there is no walk to a line. The index applies the box itself, before it
cuts its candidates to the best-named: it covers the whole oblast, and a common
name such as "шевченка" matches thousands of places there. Places named only by
a house number ("7а", "12/2б"), plots OpenStreetMap tags as places, are left out
of both (`geocode.HOUSE_NUMBER`), unless Photon knows their street: then they go
by their address, "вулиця Шевченка 55". That box takes in villages up to 15 km out
that share the city's street names, so places within 8 km of Rynok Square (the
city's own; `geocode.CITY`) come first, each source's order kept among them and
among the rest. The same name within 100 m is kept once. Answers are cached for a day.
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
four letters or more (`match.dart`, `match.ts`). A word typed whole ranks above
one it only begins, so the code "61" lists stop 61 before 610 to 619.

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
which part of it is walked on (`graph`) and one of the catalog's stops (`stops`),
and the edge each stop steps onto (`at_*`). The service rebuilds it when
any of the three is not what it holds - about 8 s, written beside the old file
and swapped in. A file from before the digests, or from before stops stepped
onto edges, lacks them, so it is rebuilt once. Without them the service still starts, logs why, and
`/api/plan` answers 503 - the map and the arrivals do not depend on it.

## Route shapes

`GET /api/shapes` is where a route physically goes: per route, the polylines its
trips follow, each marked with the feed direction it runs and listing the stops
it calls at in order, as catalog positions (`stops`). Those are the longest trip
on that shape, so a short working does not cut the list short; they are what the
Lines tab lists a line by, one direction at a time. Direction is drawn by
the clients, not served - a run both ways gets two tracks of chevrons, one per
side, spaced on screen rather than on the ground, which is why nothing here has
to be respaced per zoom. 245 KB, 33 KB gzipped before the stops were added, one ETag per
feed, and both clients ask for it only the first time something wants to draw or
list a line - opening one in the Lines tab, or the button that puts the whole
network on the map. Nobody
who opens neither pays for it.

## Keeping the city current

The feed and the footpaths change under a running service, and it follows them
without a restart (`commuterlviv/live/refresh.py`):

1. Every night at 03:30 Kyiv time (`CHECK_AT`), after the last tram and before
   the first, it wakes up. Nobody is riding, so nobody notices what follows.
2. If `walk.npz` is over 30 days old (`WALK_EVERY`), or was fetched asking for
   other ways than the code asks for now (`walk.KIND`), the footpaths are fetched
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
   minute or so. A shape the feed changed starts from the timetable. The
   learned models are fitted again on the rows it took over, rather than
   leaving the new city without them until the next `FIT_EVERY`.
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

## Stops the vehicles drive past

The feed lists every stop of a trip and has no pickup or drop-off columns, so a
stop a route never calls at looks like any other. The recording shows it. A
vehicle that calls at a stop stands near it on most trips, and one that drives
past does not (`commuterlviv/skipped.py`):

1. After each night's check (above), the last 7 days of the recording are read
   in a worker thread - only the fixes slower than 0.5 m/s that name a trip,
   through the `veh_ts` index. A week of them is about 4.8 million rows and,
   on a spinning disk, takes about 2 minutes to read and judge.
2. Each fix goes to its trip's pattern - one route and one stop list - and,
   within 40 m, to the nearest stop of that pattern. A stop's count is the
   number of trips that stood there at least once.
3. A pattern's usual count is the median over its stops. The first and last
   stops are left out: a vehicle takes its next trip's id only once it leaves
   the first, and often stands away from the last one's pole. A pattern
   under 30 trips at its usual stop is not judged.
4. A stop under a tenth of the usual count is flagged, for that route and
   direction alone. Another route through the same pole is judged on its own
   pattern.
5. The service logs the count and the first 20, and `/api/status` carries all
   of them under `skipped`, with the time of the check (`null` until the first
   night).

It only reports. A flagged stop is not always one the route skips: a pole
drawn away from where vehicles stand, or a stretch the route was diverted off
that week, looks the same. A person looks, and takes a stop off a route with a
`[[remove]]` rule in `overrides.toml` ([how it works](how-it-works.md)). The
network is built with those rules, so a removed stop is no longer on that
route's patterns to be flagged again. `python -m commuterlviv skipped` runs the
same check from the command line, `--days` and `--until` choosing the window.

On the week of 2026-09-16..23, with the rules in `overrides.toml` applied, 223
stops of a pattern were flagged: 110 stops on 47 routes. Колодзінського (0800)
northbound is the one a rider reported. Before its two rules, А16 stood there
on 0 trips of 367 at its usual stop and А53 on 3 of 349. It is still flagged
for А23, А32, А40 and А41, which have no rule. The opposite pole, 801, came out
at 0.13-0.14 of the usual count and is not flagged: southbound buses partly
stand 20-40 m short of it. Some flags gather on one stop across several
routes. Ребілітаційний центр Незламні (632, 633) is flagged on seven, whose
lines pass within 7 m of its poles while their slow fixes lie 200-550 m away.
That reads as a diversion that week, and is not checked.

## The model across restarts

What the model has learned is kept in `data/model.npz` (`commuterlviv/snapshot.py`).
The service writes it every 10 minutes (`SAVE_EVERY`) and on shutdown, and reads
it on start. The `profile` variant's hour-of-day means have a one-week
half-life, so without it every restart would throw away days of learning that
two hours of recording cannot replay.

1. On start the service reads the snapshot into a fresh model. Its indexes are
   positions in one build of the feed, so it carries what each meant - shape
   id, cell count and length per unit, the corridor key per corridor, the
   route ids the passed stops were noted under - and only what still matches
   is read back. The learned models' rows and the turnarounds hold no shape
   and are always read back, so even with no shape left that matches, the
   snapshot's time stands and step 2 does not note its rows a second time.
2. It then replays the recording from the later of the snapshot's time and two
   hours ago (`WARM_HOURS`), so the minutes between the last save and the
   restart are learned again.
3. Every weight carries the time it was earned and decays from that stamp, so
   an old snapshot needs no expiry: it fades back to the timetable on its own.
4. If the terminus model or the ETA correction has too few rows to be fitted
   (`Service.short`) - no snapshot, or one from before they were kept or
   noted with other features - the
   service learns them from the recording instead of waiting hours of service
   for them (`Service.backfill`). A process of its own, at a lower priority,
   replays the last 4 days into a fresh model, noting rows past the first day
   of them (`BACKFILL_S`, `BACKFILL_WARMUP_S`), and hands back its snapshot.
   The live model takes its rows, put before the ones it has noted itself
   since the start, and, if it started with no snapshot, everything else the
   fresh model learned, and both models are fitted again. On the recording to
   2026-10-07 that was 228 000 passed stops and 143 000 minutes of stands,
   about 27 minutes of one core and 395 MB at most; until it ends the
   uncorrected model and the rule answer. Started on 2026-10-05 at 03:00
   with no rows, the ETAs of the first 6 hours missed by 163 s rather than
   243 s, and those of the next 18 hours by about 130 s rather than 158 s.
   Stopped while it runs, the service kills that process (`kill_workers`,
   new in Python 3.14) instead of waiting out a replay that would outlast the
   container's stop timeout, so the snapshot saved on the way out is not lost.

A missing or unreadable snapshot is not an error - the model starts from the
timetable, as it did before the file existed, and the log says so. The
snapshot is about 111 MB. It also carries each route's recent early
turnarounds at its termini and the minutes of stands its departure model
learns from ([trips after this one](#trips-after-this-one)) and the passed
stops the ETA correction learns from
([seconds to each stop, corrected](#seconds-to-each-stop-corrected)). The
fitted models are not kept: they are fitted again on start.

## Accounts and registration

Accounts are required for everything except `/api/health`, for two reasons,
neither of them capacity. They carry a person's named route sets and pinned
stops between their devices, both stored as feed ids so that a rebuilt catalog
cannot quietly move them. And a watching client costs only bytes - the model runs once for the
whole city - so what the gate protects is not the CPU but the output: a tracked,
smoothed, city-wide vehicle history, handed over at 228 B/s to anyone who opens
the socket. Passwords are argon2id, sessions are opaque rows in Postgres behind
a `__Host-` cookie, and remember-me is series+token rotated on every use, where
a spent token coming back is treated as theft. `POST /api/password` with
`{"old", "new"}` keeps only the session that asked: every other session and
every remember-me token, its own included, is dropped. It answers 403 unless
`COMMUTERLVIV_PASSWORD_CHANGE` is true, and it is false by default: until an
account has a second way to prove who owns it, a stolen session could change the
password and lock the owner out. `/api/me` says which (`password_change`), so
the clients offer the change only where it works. Migrations apply themselves at
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
