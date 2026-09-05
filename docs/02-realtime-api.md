# The realtime API

Base URL: `https://track.ua-gis.com/gtfs/lviv/`

No API key. No `Authorization` header. No registration. No observed rate limit.
Plain `GET`. `http://` works too but 301-redirects to `https://` - **use https directly**
so you don't pay a redirect on every 5-second poll.

Server is `nginx/1.14.2`. **No CORS headers are sent** (verified with an `Origin:` request - the response carries
no `Access-Control-Allow-Origin`), so a browser app cannot fetch this directly. You need
a proxy or a native/server side. See [05-gotchas.md](05-gotchas.md).

## Endpoints

| Path | Format | Size | Content | Poll every |
|---|---|---|---|---|
| `static.zip` | GTFS zip | 3.8 MB | full schedule, stops, shapes | once a day |
| `vehicle_position` | GTFS-RT protobuf | ~45 KB | 436-438 live vehicles | 5-10 s |
| `trip_updates` | GTFS-RT protobuf | ~166 KB | ~535 trips, ~6 400 stop predictions | 15-30 s |
| `alerts` | - | - | **404. Not published.** Do not plan around it | - |

**There is no per-stop endpoint here.** `trip_updates` is a single city-wide feed and you
filter it client-side. If you only need arrivals at one stop,
`api.lad.lviv.ua/stops/<stop_code>` does that in one call and adds a scheduled fallback -
see [04-lad-json-api.md](04-lad-json-api.md).

Both realtime feeds are `incrementality: FULL_DATASET` - every response is the complete
current state, there is no differential mode. Just replace your whole in-memory set.

## Parsing

```sh
pip install gtfs-realtime-bindings requests
```

```python
import requests
from google.transit import gtfs_realtime_pb2

feed = gtfs_realtime_pb2.FeedMessage()
feed.ParseFromString(
    requests.get("https://track.ua-gis.com/gtfs/lviv/vehicle_position", timeout=30).content
)
```

For other languages the same official bindings exist: `gtfs-realtime-bindings` on npm,
`com.google.transit:gtfs-realtime-bindings` on Maven (this is what you want on Android),
`github.com/MobilityData/gtfs-realtime-bindings` for Go.

## `vehicle_position` - exact contents

Header:

```
gtfs_realtime_version: "2.0"
incrementality: FULL_DATASET
timestamp: 1788625036
```

One entity, verbatim from the live feed:

```
id: "3790543"
vehicle {
  trip {
    trip_id: "32262_2_0"
    schedule_relationship: SCHEDULED
    route_id: "142"
  }
  position {
    latitude: 49.7877083
    longitude: 24.0151825
    bearing: 89
    odometer: 110282.29850138922
    speed: 0
  }
  timestamp: 1788625031
  congestion_level: UNKNOWN_CONGESTION_LEVEL
  vehicle {
    id: "5476"
    label: "high_floor"
    license_plate: "603"
    wheelchair_accessible: WHEELCHAIR_INACCESSIBLE
  }
}
```

Field by field:

| Field | Meaning | Notes |
|---|---|---|
| `entity.id` | feed-internal record id | changes between polls, **do not use as vehicle key** |
| `vehicle.trip.trip_id` | joins to `trips.txt` | format `<block>_<run>_<direction>`; **may be absent** |
| `vehicle.trip.route_id` | joins to `routes.txt` | this is what you show the user |
| `vehicle.trip.schedule_relationship` | always `SCHEDULED` in practice | |
| `position.latitude/longitude` | WGS84 degrees | |
| `position.bearing` | compass degrees, 0 = north | integer-valued |
| `position.speed` | **metres per second** | multiply by 3.6 for km/h |
| `position.odometer` | metres, lifetime-ish | monotonic per vehicle, useful for dedup |
| `vehicle.timestamp` | unix seconds, when the GPS fix was taken | can lag `header.timestamp` |
| `vehicle.vehicle.id` | **stable fleet id** | use this as your vehicle key |
| `vehicle.vehicle.label` | `high_floor` or `low_floor` | accessibility, duplicated below |
| `vehicle.vehicle.license_plate` | two different things, see below | `603` or `BC9463TH` |
| `vehicle.vehicle.wheelchair_accessible` | `WHEELCHAIR_ACCESSIBLE` / `WHEELCHAIR_INACCESSIBLE` | |

### `license_plate` is not one format

Measured over a live snapshot of 436 vehicles:

| Length | Count | What it is | Example |
|---|---|---|---|
| 8-10 | 337 | real Ukrainian road plate, sometimes hyphenated | `BC9463TH`, `BC-7908-EC` |
| 3-4 | 99 | depot car number (trams/trolleybuses have no road plate) | `603`, `1204` |

Normalise by stripping `-` before comparing. Note the letters are **Latin** `BC`, not
Cyrillic `ВС`, even though they render identically - a string comparison against text
typed by a Ukrainian user will silently fail.

### Accessibility fields are redundant but consistent

In the same snapshot: 408 `high_floor` / `WHEELCHAIR_INACCESSIBLE`, 28 `low_floor` /
`WHEELCHAIR_ACCESSIBLE`. The `label` and `wheelchair_accessible` fields never disagreed.
Use either. Only ~6% of the fleet is low-floor.

Measured freshness: polling every 5 s, `header.timestamp` advanced by exactly 5-6 s each
time and the vehicle count stayed at 436. The feed is genuinely live, not cached.

## `trip_updates` - exact contents

Header says `gtfs_realtime_version: "1.0"` here (the vehicle feed says `"2.0"` -
harmless inconsistency, the wire format is identical).

```
id: "32524_8_0"
trip_update {
  trip {
    trip_id: "32524_8_0"
    start_date: "20260905"
    schedule_relationship: SCHEDULED
    route_id: "147"
  }
  vehicle { id: "5251" }
  stop_time_update {
    stop_sequence: 338
    departure { time: 1788627120 }
    stop_id: "4728"
    schedule_relationship: SCHEDULED
  }
  stop_time_update {
    stop_sequence: 339
    arrival { time: 1788627229 }
    stop_id: "4729"
    schedule_relationship: SCHEDULED
  }
  ...
}
```

Notes that matter:

- `entity.id` **is** the `trip_id` here (unlike the vehicle feed). You can key on it.
- `stop_time_update` carries **absolute unix `time`**, not a `delay` offset. Predicted
  arrival is `time` directly - no need to add it to a scheduled time.
- Only the **remaining** stops of the trip are listed, not the whole route. Measured on
  535 live trips: 1 to 32 stops each, 6 424 predictions in total. A vehicle near the end
  of its run has one or two entries.
- **The prediction horizon is ~45 minutes.** Across those 6 424 predictions the furthest
  was 44.7 min ahead, the median 22.4 min, and a few were slightly negative (a stop the
  vehicle is passing right now). Anything beyond ~45 min must come from the static
  timetable, not from here.
- The current stop gives `departure`, later stops give `arrival`. Do not assume both are
  present - check which field is set.
- `vehicle.id` here matches `vehicle.vehicle.id` in `vehicle_position`. **This is the
  join between the two realtime feeds**, and it was present on all 535 trips - the join
  is reliable in that direction. It does not go the other way: 535 trips are predicted
  but 436 vehicles report position, so some trips have no live vehicle behind them.
- `stop_sequence` values are large (338, 339, 340) - they are positions within the
  operational block, not 1-based indices into the trip. Sort by them, don't index with them.

## Combining the two feeds

```
vehicle_position.vehicle.vehicle.id  ─┐
                                      ├─ same fleet id
trip_updates.trip_update.vehicle.id  ─┘

vehicle_position.vehicle.trip.route_id ──> static routes.txt route_id
trip_updates.stop_time_update.stop_id  ──> static stops.txt stop_id
*.trip.trip_id                         ──> static trips.txt trip_id
```

That is the whole data model. Everything an app shows is a projection of these joins.
