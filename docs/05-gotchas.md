# Gotchas

Each of these cost real debugging time. Read before writing code.

## Network

**CORS differs per host - check which one you are calling.**

| Host | `Access-Control-Allow-Origin` | Browser-usable? |
|---|---|---|
| `track.ua-gis.com` (GTFS feeds) | none | **no** |
| `api.lad.lviv.ua` (JSON) | `*` | yes |

Verified by sending an `Origin:` header to both. A browser-only web app cannot fetch the
GTFS feeds at all - it needs a native app, or a small server/edge function that proxies
and re-serves them. If you proxy, add caching: one upstream fetch per 5 s serves all your
users. `api.lad.lviv.ua` needs no proxy.

**Use `https://`, not `http://`.** Plain HTTP works but answers `301 Moved Permanently`
to the https URL. At a 5-second poll that is 17 000 wasted round trips a day.

**`alerts` returns 404.** Transitland's registry entry advertises an alerts feed. It is
not served. There is no service-disruption channel in this data at all.

## Geo-blocking

The **official portals** geoblock non-Ukrainian IPs - `opendata.city-adm.lviv.ua`,
`data.gov.ua`, and `eway.in.ua` all return HTTP 403 with an HTML page titled
«Доступ заблоковано». A browser `User-Agent` does not help; it is IP-based.

**The data endpoints themselves are not blocked.** `track.ua-gis.com` and
`api.lad.lviv.ua` answered fine from outside Ukraine. Only the documentation and
dataset-description pages are unreachable. Use
`https://www.transit.land/feeds/f-u8c5-lvivavtodor~rt` as a reachable mirror of the
feed metadata.

## Identity

**`entity.id` is not a vehicle id.** In `vehicle_position`, `entity.id` is a
feed-internal record number (`3790543`) that changes between polls. The stable key is
`entity.vehicle.vehicle.id` (`5476`). Keying your map markers on `entity.id` makes every
vehicle vanish and reappear on each refresh.

In `trip_updates` the convention is different - there `entity.id` **is** the `trip_id`.

**`trip_id` can be absent.** 6 of 436 vehicles in a live snapshot had a `trip` with a
`route_id` but **no `trip_id`** - a vehicle assigned to a route but not to a scheduled
run (deadheading, or just started). Your join to `trips.txt` must tolerate this: still
show the vehicle, using `route_id`, with no headsign.

**`license_plate` is a mess.** In one 436-vehicle snapshot:

- 337 are road plates, 99 are 3-4 digit depot car numbers (`603`, `1204`) - trams and
  trolleybuses have no road plate.
- Road plates come hyphenated (`BC-7908-EC`), unhyphenated (`BC9463TH`) **and**
  space-separated (`КА 2675 РХ`).
- Worse, **the alphabet is inconsistent**: 304 use Latin letters (`BC1527AA`), 33 use
  Cyrillic (`ВС2315РО`). These render identically and are never equal as strings. The
  same route can carry both, e.g. route А21 has `BC-1038-AA` and `ВС2315РО`.

Normalise before you compare or search: strip `-` and spaces, uppercase, and transliterate
Cyrillic `А В Е І К М Н О Р С Т Х` to their Latin lookalikes `A B E I K M H O P C T X`.

## Encoding and text

Everything is **UTF-8 Cyrillic**. Route names use Cyrillic letters that look Latin:

| Displayed | Actual codepoint | Not |
|---|---|---|
| `А` in `А25` | U+0410 CYRILLIC CAPITAL A | U+0041 LATIN A |
| `Т` in `Т07` | U+0422 CYRILLIC CAPITAL TE | U+0054 LATIN T |

Hardcode these from the data, never retype them. Search must normalise both ways or
users typing on a Latin keyboard will find nothing.

## Vehicle types

**`route_type` does not distinguish trams from trolleybuses.** All 9 trolleybus routes
are marked `route_type: 3` (bus); only the 8 tram routes get `route_type: 0`. Derive the
type from `route_short_name` instead:

```python
def vehicle_type(short_name):
    if short_name.startswith("Тр"): return "trolleybus"   # Cyrillic Тр
    if short_name.startswith("Т"):  return "tram"         # Cyrillic Т
    return "bus"                                          # А
```

Check `Тр` **before** `Т` - the prefixes overlap. Alternatively read `vehicle_type`
straight from `api.lad.lviv.ua`, which gets it right.

## Colours

`route_color` equals `route_text_color` on **71 of 72 routes**. Using them as a
foreground/background pair renders invisible text. And they are not distinctive: 50
routes share `556b2f`, 14 share `FFFFFF`. Colour cannot identify a route here.

**Generate your own palette** - hash the `route_id`, or copy the per-route colours from
`api.lad.lviv.ua`, which are actually distinct.

Also: the hex has no leading `#`. Add one.

## Time

- `api.lad.lviv.ua` uses a different time format from the GTFS feeds: an RFC-1123 string
  **always labelled GMT** (`"Sat, 05 Sep 2026 17:01:53 GMT"`), not a unix integer. Parse
  with `%a, %d %b %Y %H:%M:%S %Z`, treat as UTC, then convert.
- All timestamps in the realtime feeds are **unix seconds, UTC**. The city is
  `Europe/Kiev` (per `agency.txt`) - UTC+2, UTC+3 in summer. Convert for display.
- `stop_time_update` carries an **absolute `time`**, not a `delay` offset. Do not add it
  to a scheduled time; it already is the prediction.
- `arrival_time == departure_time` on all 434 317 rows of `stop_times.txt`.
- GTFS allows times past `24:00:00` for after-midnight runs. This feed has none today
  (latest is `23:50:00`), but parse defensively - `strptime("%H:%M:%S")` throws on
  `25:30:00` and the schedule could add night service.
- `calendar_dates.txt` is **empty**, so **public holidays are not modelled**. The static
  schedule claims full weekday service on 1 January. Only the realtime feed reflects what
  is actually running.

## Stops

**Stop pairs are not linked.** No `parent_station`, no `location_type`. Strip the
`(NNN)` suffix from `stop_name` and 1061 stops collapse to 535 names - 338 appear twice,
40 three times, and some up to six times. The two directions of one street corner are
unrelated rows tens of metres apart:

```
4712  Іподром (434)  49.778119,24.014171  вул. Стрийська 179
45027 Іподром (318)  49.777684,24.013876  вул. Стрийська
```

Cluster them yourself, or "next arrivals at Іподром" will silently show one direction.

**`stop_code` is unreliable as a key.** Use `stop_id` internally. In 1061 stops:

- **137 have an empty `stop_code`** (e.g. stop `45027` above).
- Some are **not numeric**: `703-01`, `74-01`.
- Two codes are **duplicated**: code `1212` is both `Малехів, Кобилянської` (stop_id
  5196) and `Великий Дорошів, поворт на Зашків` (stop_id 2551821).
- The `(NNN)` suffix in `stop_name` matches `stop_code` with leading zeros stripped on
  only 913 of 1061 rows.

This matters because `api.lad.lviv.ua/stops/<code>` is keyed by `stop_code`, so those
137 stops cannot be queried there at all and the non-numeric ones return HTTP 400. See
[04-lad-json-api.md](04-lad-json-api.md).

## Size

`stop_times.txt` is 434 317 rows. Parsing it into memory on every app launch will be
slow on a phone. Load `static.zip` into SQLite once, index `(stop_id)` and
`(trip_id, stop_sequence)`, and refresh daily. Check `feed_info.txt.feed_version`
(currently `6.505`) to decide whether a re-import is needed.

## Coverage

Not every route is live at once. A daytime snapshot had **68 of 72** routes represented
by at least one vehicle. Overnight it will be far fewer. Absence of a vehicle means "not
running now", not "route deleted" - keep the route in your UI, sourced from static GTFS.
