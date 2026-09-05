# Where the data comes from

## The chain, one hop at a time

1. **Vehicles carry GPS trackers.** Every bus, tram and trolleybus in the municipal
   contract reports position to a tracking platform run for the city.
2. **The city road authority publishes it.** ЛКП Львівавтодор (Lvivavtodor, the
   municipal road maintenance enterprise) is the feed publisher named inside the data
   itself (`feed_info.txt` → `feed_publisher_name`). The tram and trolleybus fleet is
   operated by ЛКП Львівелектротранс (Lvivelectrotrans).
3. **It is served as GTFS-Realtime** - the worldwide standard transit format, encoded
   as Protocol Buffers - at `https://track.ua-gis.com/gtfs/lviv/`. Open, no key.
4. **Apps consume that feed.** Both EasyWay and the CityBus Lviv Android app read this
   same public feed. Neither owns the data.

## Evidence that the apps are just consumers

- **CityBus Lviv** (`ua.in.citybus.lviv`) states in its own Play Store description that
  vehicle tracking "depends on the functioning of an external source of GPS data" - it
  has no fleet relationship and goes dark when the city feed goes dark.
- **EasyWay** announced Lviv live data in 2018 as an *open data release by the city*,
  not as a proprietary integration.
- Vehicle ids, license plates and route ids shown in both apps match the values in the
  public feed exactly (e.g. vehicle `4036`, plate `135`, route `Тр32`).

**Conclusion: there is nothing to reverse-engineer.** The upstream source is public and
is a better target than either app's API.

## Do not bother with EasyWay's own API

`api.eway.in.ua` and `gps.easyway.info/api/*` are a **commercial partner API**. From
outside Ukraine they return HTTP 403 with a Ukrainian block page ("Доступ заблоковано").
The JSON-RPC-style endpoint that does answer rejects every method without a partner
contract:

```
{"status":"error","message":"Unknown method 'city/lviv'"}
```

Same data, worse access. Use the city feed.

## Licence

The feed is published on the city open-data portal under **CC-BY-4.0**.
You may build commercial apps on it. You must attribute.

Suggested attribution string:

> Дані: ЛКП «Львівавтодор» / Львівська міська рада, opendata.city-adm.lviv.ua (CC BY 4.0)

`attributions.txt` inside the static zip additionally names the operator company for
each individual route - useful if you want per-route credit.

## The seven operators

| agency_id | Name | Role |
|---|---|---|
| 89 | ЛКП Львівелектротранс | trams + trolleybuses (municipal) |
| 52 | АТП-1 | bus |
| 32 | Львівське АТП-14630 | bus |
| 31 | Міра і К | bus (marshrutka) |
| 148 | Фіакр-Львів | bus (marshrutka) |
| 327 | ТОВ Епітранс | bus |
| 10 | Успіх БМ | bus (marshrutka) |

## Canonical dataset pages

- https://opendata.city-adm.lviv.ua/dataset/lviv-public-transport-gtfs-real-time
- https://data.gov.ua/en/dataset/lviv-public-transport-gtfs-real-time
- https://www.transit.land/feeds/f-u8c5-lvivavtodor~rt (registry mirror; reachable
  from outside Ukraine, unlike the two above - see [05-gotchas.md](05-gotchas.md))
