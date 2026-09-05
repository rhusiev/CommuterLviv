# The static schedule (`static.zip`)

`https://track.ua-gis.com/gtfs/lviv/static.zip` - 3 832 152 bytes, plain zip, UTF-8 CSV
inside. Standard GTFS. Download once at app start or once a day, cache it, and key
everything else off it.

Snapshot documented here: `feed_version` **6.505**, valid **2026-09-03 → 2027-08-23**.

## What's in the box

| File | Rows | Why you need it |
|---|---|---|
| `routes.txt` | 72 | route names, colours - **required** to render anything |
| `stops.txt` | 1 061 | stop names and coordinates - **required** for arrivals |
| `trips.txt` | 15 914 | maps trip → route, direction, headsign, shape |
| `stop_times.txt` | 434 317 | the timetable itself; big, index it |
| `shapes.txt` | 33 362 | polylines to draw routes on a map |
| `calendar.txt` | 10 | which service runs on which weekdays |
| `calendar_dates.txt` | 0 | **empty** - no holiday exceptions are published |
| `agency.txt` | 7 | operator names, phones, ticket URLs |
| `attributions.txt` | 72 | per-route operator credit |
| `feed_info.txt` | 1 | publisher and validity window |

## `routes.txt`

```
route_id,agency_id,route_short_name,route_long_name,route_desc,route_type,route_url,route_color,route_text_color
88,31,А25,ТЦ Кінг Кросс - вул. Заклинських,,3,,556b2f,556b2f
91,89,Т07,вул. Ковча - Погулянка,,0,,556b2f,556b2f
92,52,А99,площа Галицька – Музей народної архітектури,,3,,f003f0,f003f0
```

- `route_short_name` is what users say out loud: `А25`, `Т07`, `Тр32`. **Cyrillic А/Т.**
- `route_long_name` is the two endpoints, `-` separated.
- `route_desc` and `route_url` are empty on all 72 rows. Don't build UI around them.
- `route_color` / `route_text_color` are hex **without** a leading `#`. They are equal to
  each other on **71 of 72 routes**, which renders text invisible if you use them as a
  pair. Worse, 50 routes share the exact colour `556b2f` and 14 share `FFFFFF`, so colour
  does not distinguish routes either. **Generate your own palette** - see
  [05-gotchas.md](05-gotchas.md).

## `stops.txt`

```
stop_id,stop_code,stop_name,stop_desc,stop_lat,stop_lon
4711,0320,ТРЦ Кінг Кросс (320),"вул. Стрийська, 30",49.774093,24.012718
```

- `stop_name` embeds a stop code in parentheses - `ТРЦ Кінг Кросс (320)`. It matches
  `stop_code` with leading zeros stripped on 913 of 1061 rows, and disagrees on the rest.
  Strip the `(NNN)` suffix for display; trust `stop_code` for the code.
- `stop_code` is **empty on some rows** (e.g. stop `45027`). Never key on it.
- `stop_desc` is the street address and is populated on **all 1061 rows**. This is your
  best tool for disambiguating the two sides of a road.
- No `location_type`, no `parent_station` - **stop pairs are not grouped**. Strip the
  `(NNN)` suffix and 1061 stops collapse to 535 distinct names: 338 names appear twice,
  40 three times, 26 four times, 5 five times, 2 six times, and only 124 are unique.
  Example:

  ```
  4712  code 0434  Іподром (434)  49.778119,24.014171  вул. Стрийська 179
  45027 code ''    Іподром (318)  49.777684,24.013876  вул. Стрийська
  ```

  ~48 m apart, opposite directions, no link between them in the data. If you want a
  "station" view you must cluster them yourself: same stripped `stop_name`, within
  ~150 m.

## `trips.txt`

```
route_id,service_id,trip_id,direction_id,trip_headsign,block_id,shape_id,wheelchair_accessible,bikes_allowed
992,224,18550_0_1,1,Авторинок (199),18550,37933,0,0
```

- `trip_headsign` is the destination stop name, with its stop code in parentheses.
- `direction_id` 0/1 - outbound/inbound as the operator defines it, not a compass.
- `block_id` equals the first segment of `trip_id`. `trip_id` is
  `<block_id>_<run>_<direction_id>`.
- `wheelchair_accessible`: `1` on 2 203 trips, `0` (no information) on 13 711.
  `bikes_allowed`: `1` on 929, `0` on 14 985. So these are partially populated -
  a `0` means unknown, not "no". For a vehicle that is actually running, prefer the
  realtime feed's per-vehicle `low_floor` / `WHEELCHAIR_ACCESSIBLE`, which is always set.
- `shape_id` is empty on 2 of 15 914 trips. Handle the missing case.

## `stop_times.txt`

```
trip_id,arrival_time,departure_time,stop_id,stop_sequence,shape_dist_traveled,timepoint
18550_0_1,07:00:00,07:00:00,5094,2,,1
```

434 317 rows. Do not parse this into memory on a phone on every launch - load it into
SQLite once with an index on `(stop_id)` and on `(trip_id, stop_sequence)`.

- `arrival_time == departure_time` on **all 434 317 rows** - no dwell time is modelled.
  Read one, ignore the other.
- `timepoint` is `1` on every row, so it carries no information.
- `shape_dist_traveled` is **empty on every row** here (it is populated in `shapes.txt`).
- No time exceeds 24 hours in this snapshot - the latest is `23:50:00`, and there is no
  after-midnight service. GTFS permits `25:30:00`-style values, so still parse
  defensively, but you will not hit it today.
- `stop_sequence` runs 1..526 and is scoped to the **block**, not the trip. A trip's own
  stops are a contiguous slice somewhere in that range - sort by it, never index with it.

## `shapes.txt`

```
shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence,shape_dist_traveled
37933,49.87316,24.04986,0,0.0
```

Order by `shape_pt_sequence` (0-based) to get the polyline for a `trips.txt.shape_id`.
`shape_dist_traveled` is cumulative metres - useful for "how far along its route is this
vehicle" if you snap the live position to the shape.

## `calendar.txt`

```
service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date
31,1,1,1,1,1,0,0,20260903,20270823
```

Ten service patterns, covering weekday / Saturday / Sunday / weekday+Sat / all-week
combinations, all with the same 2026-09-03 → 2027-08-23 window.
`calendar_dates.txt` is **empty**. That means public
holidays are not modelled at all - the static schedule will claim normal weekday service
on New Year's Day. If holiday accuracy matters, that must come from the realtime feed
(which reflects what is actually running) or your own calendar.

## `agency.txt` / `attributions.txt`

`agency.txt` has phone numbers and, for Lvivelectrotrans, a ticket-purchase URL
(`https://tickets.lvivelectrotrans.com.ua/`) - worth surfacing in a "buy a ticket" button.

`attributions.txt` maps each `route_id` to the operating company with
`is_producer`/`is_operator`/`is_authority` flags. Use it to satisfy CC-BY per route.
