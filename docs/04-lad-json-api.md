# `api.lad.lviv.ua` - the easy JSON option

The city's own web tracker exposes JSON that has **already done every GTFS join for
you**: route name, colour, vehicle type, destination and English names come back inline,
so you never touch protobuf or the 3.8 MB static zip.

It also **sends `Access-Control-Allow-Origin: *`**, so unlike `track.ua-gis.com` it works
directly from a browser with no proxy.

It is **undocumented and unversioned** and exists to serve one website. Excellent for a
prototype or a stop-arrivals screen. Keep a GTFS fallback path if you ship it.

## Endpoints

| Path | Returns | Use it for |
|---|---|---|
| `/stops/<stop_code>` | JSON | **arrivals at one stop** - the best endpoint here |
| `/transport?latitude=&longitude=` | JSON | vehicles within ~1 km of a point |
| `/stops` | HTML (865 KB) | nothing - take stops from `static.zip` |
| `/routes` | HTML (1.1 MB) | nothing - take routes from `static.zip` |

The two list pages are server-rendered HTML with the data embedded. Scraping them is
fragile; the static zip has the same content in CSV.

---

## `/stops/<stop_code>` - arrivals at a stop

```
GET https://api.lad.lviv.ua/stops/61
```

```json
{
  "name": "Площа Ринок",
  "eng_name": "Rynok square",
  "latitude": 49.841463,
  "longitude": 24.032271,
  "code": 61,
  "transfers": [
    {
      "id": "1627", "route": "Т01", "vehicle_type": "tram", "color": "#E42D24",
      "shape_id": "37964", "direction_id": 1,
      "end_stop_name": "Погулянка", "end_stop_eng_name": "Pohulianka",
      "end_stop_code": 197
    }
  ],
  "timetable": [
    {
      "route_id": "1627", "route": "Т01", "vehicle_type": "tram", "color": "#E42D24",
      "arrival_time": "Sat, 05 Sep 2026 17:01:53 GMT",
      "time_left": "4хв",
      "vehicle_id": "1944", "location": [49.83642, 24.0225], "bearing": 311,
      "direction": 1, "direction_id": 1, "lowfloor": false, "shape_id": "37964",
      "end_stop": "Погулянка", "end_stop_name": "Погулянка",
      "end_stop_eng_name": "Pohulianka", "end_stop_code": 197
    }
  ]
}
```

`transfers` = every route that serves this stop (a static "routes here" list).
`timetable` = the actual upcoming arrivals, soonest first.

### Two kinds of `timetable` entry

This is the field that matters most:

| | Live prediction | Scheduled fallback |
|---|---|---|
| `scheduled` | **absent** | `true` |
| `vehicle_id`, `location`, `bearing`, `direction` | present | **absent** |
| Everything else | present | present |

Measured across 23 stops / 76 entries: **60 live, 16 scheduled**. When no vehicle is
being tracked for an upcoming run, the endpoint falls back to the timetable rather than
showing nothing. `trip_updates` cannot do this - it only knows about tracked vehicles.

**Always branch on `"scheduled" in entry`** before reading `location` or `vehicle_id`, or
you will get a `KeyError`. Label scheduled rows differently in the UI - they are not
real-time and can be minutes off.

### Fields

| Field | Notes |
|---|---|
| `arrival_time` | RFC-1123 string, **always GMT** - `"Sat, 05 Sep 2026 17:01:53 GMT"`. Parse with `%a, %d %b %Y %H:%M:%S %Z`, treat as UTC, convert to `Europe/Kiev` for display |
| `time_left` | pre-formatted Ukrainian, e.g. `"4хв"` (= 4 min). Convenient, but compute your own if you localise |
| `route` / `route_id` | `route_id` is the GTFS `route_id`; `route` is `route_short_name` |
| `vehicle_type` | `bus` / `tram` / `trolleybus` - **correct**, unlike GTFS `route_type` |
| `color` | hex **with** `#`, genuinely distinct per route |
| `end_stop_name` / `end_stop_eng_name` | destination, with an English name - the static feed has no English at all |
| `location` | `[lat, lon]`, **lat first**, live entries only |
| `lowfloor` | boolean |

### Measured behaviour

- **~3.3 arrivals per stop**, horizon **0 to 58 minutes** (median 8 min).
- Unknown code → `404` `Bad argument, stop with code N not found`.
- One direction per call. The two sides of a street corner are separate codes -
  Іподром is `434` and `318`. Query both and merge if you want a corner view.

### Getting a `stop_code` - three traps

The endpoint is keyed by **`stop_code`**, not `stop_id`. Leading zeros are optional
(`/stops/61` and `/stops/0061` are identical). Mapping from the static feed is not clean:

1. **137 of 1061 stops have an empty `stop_code`** and simply cannot be queried. Fall
   back to `trip_updates` for those.
2. **Some codes are not numeric.** `703-01` and `74-01` return
   `400 Bad argument, 703-01 is not a number`.
3. **Codes are not unique.** `1212` is both `Малехів, Кобилянської` (stop_id 5196) and
   `Великий Дорошів, поворт на Зашків` (stop_id 2551821). Check `name`/`latitude` in the
   response matches the stop you meant.

---

## `/transport?latitude=&longitude=` - vehicles near a point

```
GET https://api.lad.lviv.ua/transport?latitude=49.84&longitude=24.03
```

Both parameters are required and must be spelled in full. Short forms `lat`/`lng` give:

```
400  Bad argument: latitude must be between -90 and 90, longitude between -180 and 180
```

```json
[
  {
    "id": "4075", "route": "Т25", "routeId": "1628", "vehicle_type": "trolleybus",
    "color": "#E85222", "direction": 1,
    "location": [49.83324432373047, 24.0356388092041],
    "bearing": 111, "speed": 0, "lowfloor": false
  }
]
```

| Field | Relation to GTFS |
|---|---|
| `id` | `vehicle.vehicle.id` in the RT feed |
| `routeId` | **exactly** `routes.txt.route_id` |
| `route` | `routes.txt.route_short_name` |
| `speed` | **metres per second**, same unit as GTFS-RT (`2.22` = 8 km/h) |
| `direction` | `trips.txt.direction_id` |
| `location` | `[lat, lon]` - lat first |

### Cautions

- **The radius is ~1 km and you cannot change it.** From the city-centre query: 45
  vehicles, nearest 169 m, farthest 978 m. There is no `radius` parameter.
- **One call sees a small slice of the city.** Four widely spaced queries returned 46, 7,
  9 and **0** vehicles - 62 unique vehicles on 38 routes, out of ~436 vehicles on 68
  routes live at that moment. Covering Lviv means tiling a ~1.5 km grid and deduplicating
  by `id` - many requests to replace one 45 KB protobuf fetch. Use `vehicle_position` for
  anything map-wide.
- No `trip_id`. For arrivals use `/stops/<code>` instead.

---

## Why this API is worth using at all

It answers two questions the static GTFS gets wrong or omits entirely:

**Tram vs trolleybus.** In static GTFS all 9 trolleybus routes are `route_type: 3` (bus);
only the 8 tram routes are `route_type: 0`. This API is correct:

```
Т08  routeId 903   route_type 0  ->  tram
Т25  routeId 1628  route_type 3  ->  trolleybus
А01  routeId 90    route_type 3  ->  bus
```

Using GTFS alone, derive it from the name prefix instead - see [05-gotchas.md](05-gotchas.md).

**English names.** `eng_name` and `end_stop_eng_name` have no equivalent anywhere in the
static feed, which is Ukrainian-only.

Its per-route `color` values are also distinct, which `routes.txt` colours are not.

## Prior art

`https://github.com/vbhjckfd/timetable-api-node` - a NodeJS reimplementation of this API.
It loads `static.zip` into SQLite and layers `track.ua-gis.com` realtime on top. Useful
as a reference for the joins even if you write your own.
