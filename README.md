# CommuterLviv

Live arrival times for Lviv's trams, trolleybuses and buses: when the next one
actually arrives, not when the timetable says it should.

The city publishes where its vehicles are. This project map-matches every fix
onto its trip's shape, learns how long each 100 m of road is taking right now
and at this hour on the days before, and turns that into an arrival time for
every stop ahead of every vehicle. It also plans door-to-door journeys on those
live times, shows traffic on the streets the vehicles drive, and keeps an
account's routes and stops in sync between devices.

It is a server, a web app and an Android app - on F-Droid, and as APKs on the
[releases page](https://github.com/rhusiev/CommuterLviv/releases) - on one
version line, which the app joins only when it changes.

## Running it

Docker Compose, from `main`:

```sh
git clone https://github.com/rhusiev/CommuterLviv.git && cd CommuterLviv
cp .env.example .env      # a database password, and the origin you serve on
docker compose up -d --build
docker compose exec service python -m commuterlviv admin invite
```

The last line prints one registration link. Open it, pick a username, and the
map is yours. The stack is Postgres for the accounts, the service, the collector
whose recording the model warms on, a basemap server for Lviv, and Caddy in
front on `127.0.0.1:8080`. Nothing has to be fetched or built by hand - the
feed, the footpaths for the planner and the map tiles are all fetched on the
first start and refreshed on their own.

[docs/deployment.md](docs/deployment.md) has the rest: TLS, running behind an
existing proxy, updating, what it reaches out to, moving a recording in.

Without Docker, for development:

```sh
pip install -r requirements.txt -r requirements-live.txt
python3 -m commuterlviv serve     # the model, over HTTP and websockets
python3 -m commuterlviv collect   # record the live feeds into data/feed.db
python3 -m commuterlviv walk      # fetch the footpaths, for the journey planner
python3 -m commuterlviv plan      # door to door: walk, ride, walk
python3 -m commuterlviv admin     # invite links and accounts
```

`serve` needs a Postgres URL in `COMMUTERLVIV_DATABASE_URL` and the allowed
origins in `COMMUTERLVIV_ORIGINS`. Everything it downloads or learns lives in
`data/`. The web app is `cd web && npm install && npm run dev`, the phone app
`cd mobile && flutter run`.

## Using it

- **Map.** Every tracked vehicle, moving smoothly between the five-second
  updates, with its route number and heading. Pick routes to see their stops;
  tap a stop for the next arrival of every route through it, tap a vehicle for
  every stop it will reach and when.
- **Times.** Pinned stops and their arrivals, live. Arrivals beyond the current
  trip - the vehicle's next run - are in italics with a schedule mark.
- **Plan.** Tap where you are and where you are going. You get ways there ranked
  by arrival, each ride marked live or timetabled, with the backups behind each
  ride should you miss it. Sort by fastest, less walking, fewer changes or most
  backups, set your walking speed, or plan for later. An answer that looks
  wrong can be reported, and is kept with the live data it ran on. Follow an
  option and it tells you what to do next as you go - which stop to walk to,
  when the vehicle is due, where to get off - from where you are, which stays
  on the device. The app can go on with the screen off, on a notification that
  sounds when to get off.
- **Layers.** The whole network, traffic per street, and eight map styles -
  colorful, natural, muted and gray, each light and dark.

Search finds stops, addresses and places. The app is in Ukrainian, or English
for a browser or phone set to it.

## Accuracy

Measured offline, by replaying a recording of the city's feeds and scoring every
prediction against the moment the vehicle actually passed the stop. On one
recording of 717 685 stop crossings, 15.4 million predictions out to 45 minutes
ahead, every approach scored on the same predictions:

| | mean error | median | within 1 min | within 2 min |
| --- | --- | --- | --- | --- |
| this model (`profile`) | 134 s | 74 s | 44.0% | 64.9% |
| the timetable | 876 s | 624 s | 9.5% | 16.9% |
| the city's `trip_updates` feed | 1442 s | 163 s | 24.8% | 41.5% |

The error grows with how far ahead the prediction is:

| how far ahead | 0-1 min | 1-2 min | 2-5 min | 5-10 min | 10-20 min | 20-45 min |
| --- | --- | --- | --- | --- | --- | --- |
| this model, mean error | 17 s | 28 s | 44 s | 74 s | 125 s | 240 s |
| the city's feed, mean error | 824 s | 826 s | 843 s | 884 s | 1079 s | 2469 s |

The city's feed has outages that inflate its mean. Its public arrivals board
(`api.lad.lviv.ua`) is the fairer opponent; on the 1.16 million predictions it
also made, the model's mean error is 101 s and 51% land within a minute, against
the board's 134 s and 41%. Over 19 days, cut by day, the served model's mean
error stayed between 107 s and 165 s.

The evaluation code and every report are on the `development-archive` branch.
[docs/how-it-works.md](docs/how-it-works.md) traces one GPS fix from the feed to
a scored prediction.

## Performance

- **The model** runs once for the whole city, whatever the number of users:
  every vehicle's fix folded in every 5 s, the model stepped every 60 s, about
  26 700 road cells. An arrival time is O(1) per stop - a subtraction of two
  cumulative sums.
- **A client** costs only bytes: about 228 B/s on the websocket.
- **A journey search** takes about 0.5 s, footpaths with hills included.
- **Memory** is about 250 MB for the service and as much for the collector.
- **Disk** is the recording: about 0.7 GB a day, 30 days kept.
- **The web app** is 89 kB of gzipped script, plus 265 kB of MapLibre loaded
  with the map.
- **A restart** costs nothing the model learned: it is saved every 10 minutes
  and on shutdown and read back on start. A new timetable is taken over at night
  without a restart, keeping everything learned on routes it did not change.

## Documentation

| | |
| --- | --- |
| [deployment](docs/deployment.md) | running it in production with Docker |
| [how it works](docs/how-it-works.md) | from a GPS fix to a scored prediction, step by step |
| [the service](docs/service.md) | the API, the journey planner, traffic, search, nightly updates, accounts |
| [the collector](docs/collector.md) | the recording: failure handling, disk, merging and copying |
| [the clients](docs/clients.md) | the web app and the phone app |
| [development](docs/development.md) | branches, checks, versions and releases |
| [mobile/README.md](mobile/README.md) | building the phone app |

## License

MIT - see [LICENSE](LICENSE)
