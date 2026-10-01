# Deployment

Docker Compose is the deployment. Five containers, one command, nothing
installed on the host but Docker:

| container | what it is |
| --- | --- |
| `commuterlviv_db` | Postgres 16, the accounts |
| `commuterlviv_service` | the model, the API and the websocket |
| `commuterlviv_collector` | the recording the model warms on, `data/feed.db` |
| `commuterlviv_tiles` | the basemap for Lviv, cut and refreshed by itself |
| `commuterlviv_web` | Caddy, serving the web app and passing the rest back |

```sh
git clone https://github.com/rhusiev/CommuterLviv.git && cd CommuterLviv
cp .env.example .env      # then edit it: a password, and the origin you serve on
docker compose up -d --build
docker compose exec service python -m commuterlviv admin invite
```

That last line prints one registration link. Open it, pick a username, and the
map is yours. Deploy from `main`: it only ever holds released versions.

Two lines of `.env` decide everything and neither has a safe guess:
`POSTGRES_PASSWORD`, and `COMMUTERLVIV_ORIGINS` - the exact origins allowed to
make unsafe requests, scheme and host and port, no trailing slash. Everything
else in the file is commented out with its default beside it.

A machine with 2 vCPU, 2 GB of RAM and 40 GB of disk is enough. The service and
the collector sit at about 250 MB each, and the service holds a second city for
the minute a new feed is built beside the old one. Disk is the recording: about
0.7 GB a day, 30 days kept.

## Updating

```sh
git pull
docker compose up -d --build
```

The volumes keep the recording, the learned model, the footpaths, the accounts
and the basemap, so an update restarts into the same state. The service answers
its health check once the city is built and the model warmed, about a minute.

## Day to day

`docker compose logs -f service` is the rest of the interface, with these beside
it:

```sh
docker compose exec service python -m commuterlviv admin users
docker compose exec service python -m commuterlviv admin disable <name>
docker compose exec service python -m commuterlviv admin delete <name> --yes
docker compose exec service python -m commuterlviv admin operator <name>
```

`disable` locks an account and ends its sessions and can be undone; `delete`
erases it and everything hanging off it and cannot. `operator` grants one
thing: the right to read `GET /api/status`, which reports engine health, how
many clients are connected and how much the service is pushing. Being signed in
does not carry that - to anyone without the flag the endpoint is a 404, so it
does not even admit to being there. `--undo` takes it back.

`docker compose logs -f collector` prints one line every 5 minutes, which is the
collector's whole health check - see [the collector](collector.md).

## In front of it

**Caddy serves the app and the service on one origin**, passing `/api` and `/ws`
back, `/tiles` to the basemap, and serving `index.html` for every other path.
One origin is what makes the `__Host-` session cookies work with no
cross-origin rules at all, and the `index.html` fallback is what keeps
`/join/<code>` from being a 404.

By default Caddy is published on `127.0.0.1:8080`, on the assumption that this
machine already has something terminating TLS. If it does not, and the domain
points here, hand Caddy the domain and it gets a certificate itself:

```sh
echo 'COMMUTERLVIV_SITE_ADDRESS=commuterlviv.r1a.nl' >> .env
docker compose -f docker-compose.yml -f docker-compose.tls.yml up -d
```

**Behind a proxy that is already running**, publish nothing at all. This
overlay drops the host port and puts the web container on the proxy's own
docker network instead, so the proxy reaches it by name and the stack has no
door to the outside:

```sh
echo 'CADDY_NETWORK=caddy' >> .env      # the existing network's name
docker compose -f docker-compose.yml -f docker-compose.proxy.yml up -d
```

```caddy
commuterlviv.example.com {
	reverse_proxy commuterlviv_web:8080
}
```

That is the whole of it: `/ws` is an ordinary upgrade through the same
`reverse_proxy` and needs no separate rule, and the outer proxy holds the
certificate so `docker-compose.tls.yml` is not used with this. The outer proxy
has to be on that network too. Rate limits stay per real client because Caddy
sets `X-Forwarded-For` and the service reads the first entry - which is also
why `COMMUTERLVIV_TRUST_PROXY` must stay off for a deployment where the port is
reachable directly.

## The basemap

The map is drawn from vector tiles, and by default they come from this stack and
not from a public server. The `tiles` container (`deploy/tiles.sh` on the
`versatiles/versatiles` image) does it on its own:

1. On its first start it cuts a Lviv extract out of the VersaTiles planet over
   HTTP range requests, so only the bbox crosses the wire - about 10-20 MB at
   maxzoom 14. It fetches the sprites and glyphs (`frontend.br.tar.gz`) and the
   eight styles, with their URLs rewritten to `$COMMUTERLVIV_WEB_BASE/tiles` -
   or the first of `COMMUTERLVIV_ORIGINS` - because a style names its sprite,
   glyph and tile URLs absolutely and the phone's style reader does not resolve
   relative ones.
2. It serves them on port 8080 of the internal network. Caddy passes `/tiles/*`
   to it and marks the answers cacheable for a week.
3. Every hour it checks the files' age. Anything older than 30 days
   (`REFRESH_DAYS`) is fetched again beside the old file and swapped in, and
   the server is restarted only if the extract or the sprites changed. A failed
   fetch keeps what is there and is tried again the next hour.

So the public servers see one machine once a month, whatever the number of
users. The phone keeps tiles on disk for 90 days; the browser keeps them in its
HTTP cache for the week Caddy allows.

Neither app is built knowing any of it. The service reports
`COMMUTERLVIV_SELF_TILES` on `/api/health`, and the web app and the phone app
both ask before they draw a map - so one web image and one APK work under any
domain, and pointing the phone at a different deployment follows that
deployment's map too.

To use `tiles.versatiles.org` instead, set `COMMUTERLVIV_SELF_TILES=false` and
run `docker compose up -d --scale tiles=0`. Every phone and browser then asks
that server for every tile, and it learns each visitor's address and where they
look.

## What it reaches out to

| Host | Who asks | How often | Doing without it |
| --- | --- | --- | --- |
| `track.ua-gis.com` | the service and the collector | every 5 s | nothing to do - this *is* the data |
| `api.lad.lviv.ua` | the collector | every 60 s | only the recording misses the city's arrivals board, which the evaluation compares against |
| `download.versatiles.org`, `tiles.versatiles.org`, `github.com` | the tiles container | once on the first start, then every 30 days | `COMMUTERLVIV_SELF_TILES=false`, and every client asks `tiles.versatiles.org` per tile instead |
| `overpass-api.de` | the service | once per volume, then every 30 days at night | `COMMUTERLVIV_BUILD_PLANNER=false` and copy `data/walk.npz` in |
| `s3.amazonaws.com` (Terrarium elevation tiles) | the service | 120 tiles with every Overpass fetch | copy a `data/walk.npz` that has heights in; unreachable, the service walks on the level and asks again next boot |
| `photon.komoot.io` | the service | per address search, cached for a day | `COMMUTERLVIV_PHOTON_URL` to a self-hosted Photon, or empty |

## Moving a recording in

A recording from another machine is worth carrying: the service warms on it,
and the evaluation on `development-archive` is run against one. Copy it into the
volume before the collector starts writing a new one:

```sh
docker compose up -d db service                  # creates the volume
docker compose cp feed.db service:/app/data/feed.db
docker compose cp walk.npz service:/app/data/walk.npz
docker compose up -d                             # the collector joins in
```

`walk.npz` is pure OpenStreetMap and host-independent, so copying it saves an
Overpass fetch; `transfers.npz` is not - it is numbered against the catalog it
was built with, so it is always built on the far side. Take the recording with
SQLite's backup and not a file copy - see [the collector](collector.md#two-collectors-at-once).
Stop the old collector first: two of them poll the same feeds twice for no
extra information.

## Worth knowing

- **First boot takes a few minutes.** The static GTFS feed has to be fetched and
  the city's geometry built from it, and the tiles container cuts its extract.
  All of it is cached in the volumes, so every boot after that is about a
  minute.
- **The journey planner builds itself on first boot**, in a background task, so
  `/api/plan` is a 503 for the two or three minutes it takes and everything else
  serves normally. To do it by hand instead - or to keep the deployment off
  Overpass entirely - set `COMMUTERLVIV_BUILD_PLANNER=false` and either copy
  `data/walk.npz` and `data/transfers.npz` in, or run
  `docker compose exec service python -m commuterlviv walk` and then
  `... plan --build`.
- **The model is kept in the volume**, in `data/model.npz`, every 10 minutes and
  on shutdown, so a restart or an update keeps what it learned - see
  [the model across restarts](service.md#the-model-across-restarts).
- **`COMMUTERLVIV_SECURE_COOKIES` defaults to true** and browsers only accept
  `__Host-` cookies over HTTPS. Serving over plain HTTP with it left on gives a
  login that silently never sticks.
- **The compose project is named `commuterlviv`**, so the volumes are
  `commuterlviv_postgres_data`, `commuterlviv_service_data` and
  `commuterlviv_tiles_data` whatever the checkout directory is called.
  `COMMUTERLVIV_TILES` puts the basemap in a host directory instead.
- **The host's time zone does not matter.** Every stored timestamp is a Unix
  epoch, and the nightly check and the timetable read Kyiv time explicitly.
- **Only one machine should record.** The collector is part of the stack, so a
  second deployment - a staging copy, a laptop - should be brought up with
  `--scale collector=0`.
