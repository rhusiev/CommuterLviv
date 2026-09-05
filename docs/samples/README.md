# Reference samples

Captured live on 2026-09-05 from the endpoints described in [../02-realtime-api.md](../02-realtime-api.md).
Kept so an agent can inspect real shapes without network access. **Snapshots, not truth** -
the live feed is the authority.

| File | Source |
|---|---|
| `routes.txt`, `agency.txt`, `calendar.txt`, `feed_info.txt`, `attributions.txt` | complete, from `static.zip` (feed_version 6.505) |
| `stops.head.txt`, `trips.head.txt`, `stop_times.head.txt`, `shapes.head.txt` | header + 20 rows of the large tables |
| `vehicle_position.sample.txt` | decoded protobuf: header + 3 entities of 436 |
| `trip_updates.sample.txt` | decoded protobuf: header + 2 entities of 535 |
| `lad_transport.sample.json` | `api.lad.lviv.ua/transport?latitude=49.84&longitude=24.03` |
| `lad_stop_61.sample.json` | `api.lad.lviv.ua/stops/61` - arrivals at Площа Ринок |
