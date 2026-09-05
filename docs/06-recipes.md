# Recipes

Runnable code is in [`examples/`](examples/). Every snippet below was executed against
the live feed.

```sh
pip install gtfs-realtime-bindings requests
cd examples
```

`gtfs_lviv.py` is the shared helper - it caches `static.zip` in `~/.cache/lviv-gtfs`
for 24 h, parses any GTFS table into dicts, fetches and decodes a realtime feed, and
maps a route name to a vehicle type.

## Show every vehicle in the city

```sh
python3 live_map.py
```

```
436 vehicles @ Sat Sep  5 19:39:35 2026

  А15 bus        49.82753,23.93121   0.0 km/h brg  32  veh 907   BC1527AA      Приміський вокзал - Медової Печери
  А18 bus        49.83587,24.06968  21.0 km/h brg  94  veh 3719  BC-5364-OA    вул. Суботівська - Глинянський Тракт
  А21 bus        49.84534,24.02651  20.0 km/h brg 306  veh 838   ВС2315РО      Кільцева дорога Три слони
```

The whole join is three lines:

```python
routes = by_id("routes.txt", "route_id")
for e in feed("vehicle_position").entity:
    r = routes.get(e.vehicle.trip.route_id, {})
```

Key your map markers on `e.vehicle.vehicle.id`, never `e.id`.

## Arrivals at a stop - the easy way

One HTTP call, no protobuf, no static zip, and it works from a browser
(`api.lad.lviv.ua` sends `Access-Control-Allow-Origin: *`):

```sh
python3 stop_arrivals.py 61            # by stop_code
python3 stop_arrivals.py Погулянка     # by name, resolved through static GTFS
```

```
Площа Ринок (Rynok square) - code 61
    Т02 tram         1.8 min     veh 1915   -> Пасічна
    Т02 tram        12.2 min     veh 1924   -> Пасічна

Погулянка (Pohulianka) - code 197
    Т07 tram         6.4 min     sched      -> Отця Омеляна Ковча
    Т01 tram        10.4 min     sched      -> Залізничний вокзал
```

The `sched` rows are the reason to prefer this endpoint: when no vehicle is tracked for
an upcoming run it falls back to the timetable instead of showing nothing. Branch on it,
because the live-only fields are absent:

```python
if t.get("scheduled"):
    label = "scheduled"                    # no vehicle_id / location / bearing
else:
    label = f"vehicle {t['vehicle_id']} at {t['location']}"
```

`arrival_time` is an RFC-1123 string in GMT, not a unix integer:

```python
when = datetime.datetime.strptime(t["arrival_time"], "%a, %d %b %Y %H:%M:%S %Z") \
        .replace(tzinfo=datetime.timezone.utc)
```

Keyed by `stop_code`, not `stop_id` - and 137 of 1061 stops have no code, a few are
non-numeric, and two codes are duplicated. Resolve names through `static.zip` (as the
script does) and fall back to `trip_updates` for stops it cannot address. See
[04-lad-json-api.md](04-lad-json-api.md).

## Arrivals at a stop - the stable way

```sh
python3 arrivals.py 49.8419 24.0315     # Площа Ринок
```

```
Площа Ринок - 1 stop(s), 4 arrivals

  Т02 tram         3.5 min  19:43  veh 1901  Площа Ринок (61)
  Т01 tram         8.8 min  19:49  veh 6116  Площа Ринок (61)
  Т01 tram        21.6 min  20:01  veh 1944  Площа Ринок (61)
```

Three things this example gets right, and you must too:

1. It collects **all stops within 150 m**, not one `stop_id`, because the two directions
   of a street corner are separate unlinked rows.
2. It reads `stu.arrival.time or stu.departure.time` - only one of the two is set,
   depending on whether the vehicle has reached that stop yet.
3. `time` is an **absolute unix timestamp**, so the countdown is `when - now`. There is
   no `delay` to add to a scheduled time.

Beyond ~45 minutes there are no predictions; fall back to `stop_times.txt` - or use
`api.lad.lviv.ua/stops/<code>` above, which does that fallback for you.

Use this GTFS path when you need stops that `api.lad.lviv.ua` cannot address, or when you
want one city-wide fetch instead of one request per stop.

## Draw a route on a map

```python
from gtfs_lviv import table
import collections

trips = table("trips.txt")
shape_id = next(t["shape_id"] for t in trips if t["route_id"] == "142")

pts = collections.defaultdict(list)
for r in table("shapes.txt"):
    pts[r["shape_id"]].append(r)

line = [(float(p["shape_pt_lat"]), float(p["shape_pt_lon"]))
        for p in sorted(pts[shape_id], key=lambda p: int(p["shape_pt_sequence"]))]
```

A route has a different `shape_id` per direction, so pick by `direction_id` too.
Two of 15 914 trips have an empty `shape_id` - guard for it.

## Poll efficiently

```python
last = 0
while True:
    msg = feed("vehicle_position")
    if msg.header.timestamp != last:      # skip redraw if nothing moved
        last = msg.header.timestamp
        render(msg.entity)
    time.sleep(5)
```

Both feeds are `FULL_DATASET`: every response is the complete current state, so replace
your whole in-memory set rather than merging. 45 KB every 5 s is ~780 MB/month if you
never stop - on mobile, poll only while the map is visible, and back off to 30 s when
backgrounded.

## Serve it to a browser

A browser cannot fetch `track.ua-gis.com` directly - there are no CORS headers. Proxy it
and cache, so one upstream fetch serves every client:

```python
from flask import Flask, Response
import requests, time

app = Flask(__name__)
_cache = {"t": 0, "body": b""}

@app.get("/vehicles.pb")
def vehicles():
    if time.time() - _cache["t"] > 5:
        _cache["body"] = requests.get(
            "https://track.ua-gis.com/gtfs/lviv/vehicle_position", timeout=30).content
        _cache["t"] = time.time()
    return Response(_cache["body"], mimetype="application/x-protobuf",
                    headers={"Access-Control-Allow-Origin": "*"})
```

## Build for Android

Use the official Java bindings rather than porting the Python:

```gradle
// check Maven Central for the current version
implementation 'com.google.transit:gtfs-realtime-bindings:+'
```

```java
FeedMessage feed = FeedMessage.parseFrom(inputStream);
for (FeedEntity e : feed.getEntityList()) {
    VehiclePosition v = e.getVehicle();
    v.getVehicle().getId();          // stable fleet id
    v.getPosition().getLatitude();
}
```

Import `static.zip` into Room/SQLite once on first launch - `stop_times.txt` alone is
434 317 rows and must not be parsed on the UI thread or on every start. Re-import only
when `feed_info.txt.feed_version` changes.

## Attribute correctly

The feed is CC-BY-4.0. Put this somewhere visible:

> Дані: ЛКП «Львівавтодор» / Львівська міська рада, opendata.city-adm.lviv.ua (CC BY 4.0)

`attributions.txt` gives the operating company per `route_id` if you want per-route credit.
