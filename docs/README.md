# Lviv public transport - live data API

Everything needed to build an app on Lviv's real-time public transport data.
All findings verified live on 2026-09-05 against the running endpoints.

**Short version:** the city publishes standard GTFS + GTFS-Realtime at
`https://track.ua-gis.com/gtfs/lviv/`. No API key, no registration, no rate limit.
This is the same feed EasyWay and the CityBus Lviv Android app consume.

## Read in this order

| File | What it answers |
|---|---|
| [01-overview.md](01-overview.md) | Who publishes the data, who else uses it, what you may legally do with it |
| [02-realtime-api.md](02-realtime-api.md) | The live endpoints - every field, with real sample values |
| [03-static-gtfs.md](03-static-gtfs.md) | The schedule zip - every file, every column, row counts |
| [04-lad-json-api.md](04-lad-json-api.md) | A simpler pre-joined JSON API - **including a one-call arrivals-at-a-stop endpoint** |
| [05-gotchas.md](05-gotchas.md) | The traps. Read this before writing code |
| [06-recipes.md](06-recipes.md) | Task-oriented code: live map, arrivals board, route shapes |

## 60-second start

```sh
pip install gtfs-realtime-bindings requests
python3 examples/live_map.py
```

```
436 vehicles @ Sat Sep  5 19:33:04 2026

 Тр22  49.78771,24.01518    0.0 km/h  brg  89  veh 5476 plate 603  Університет - Городоцька - Автовокзал
 Тр32  49.84012,24.02009   18.0 km/h  brg 231  veh 4036 plate 135  Університет - вул. Суботівська
```

## Scale of the data

- **436-438** vehicles live at once (daytime)
- **72** routes: 55 bus (`А..`), 8 tram (`Т..`), 9 trolleybus (`Тр..`)
- **7** operating companies
- **1061** stops, **15 914** trips, **434 317** stop times
- Vehicle positions refresh **every ~5 seconds**

## Layout

```
docs/
  01-overview.md      02-realtime-api.md   03-static-gtfs.md
  04-lad-json-api.md  05-gotchas.md        06-recipes.md
  examples/
    gtfs_lviv.py      shared helpers: cached static.zip, RT fetch, vehicle type
    live_map.py       every vehicle in the city, route names joined
    arrivals.py       arrivals near a coordinate, from the GTFS trip_updates feed
    stop_arrivals.py  arrivals at one stop, one call to api.lad.lviv.ua
  samples/            real captured responses, for offline reference
```

## Recommended architecture

Import `static.zip` into SQLite once a day; poll `vehicle_position` every 5-10 s and
`trip_updates` every 15-30 s; join on `route_id`, `trip_id`, `stop_id`, and `vehicle.id`.

For a **stop-arrivals screen**, `api.lad.lviv.ua/stops/<stop_code>` is much less work and
adds a scheduled fallback the GTFS feed cannot give you - but it is undocumented, and 137
of 1061 stops have no `stop_code` and cannot be addressed there. Keep `trip_updates` as
the fallback path.

Do not use `api.lad.lviv.ua` for **map-wide** views: its `/transport` radius is ~1 km,
so covering the city takes dozens of calls instead of one 45 KB protobuf fetch.

## Verification status

Every number, endpoint and field in these docs was measured against the live feed on
2026-09-05, not copied from documentation. The example scripts were executed and their
real output is quoted. Re-run `examples/live_map.py` to confirm the feed is still up
before trusting any of it.
