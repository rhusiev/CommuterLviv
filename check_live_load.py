"""What a live push service would actually cost, measured rather than guessed.

Phase 7's first open question. Three numbers decide it: how much traffic the
city generates, how much CPU one model update costs, and how many bytes a
client has to be sent per second. The first and third come from the recording,
the second from replaying a peak hour with and without prediction.

The model is shared: every client watches the same city, so CPU is per server,
not per client. Only the bytes are per client.
"""
import datetime
import gzip
import json
import sqlite3
import time

import numpy as np

from commuterlviv import network, replay

T0 = datetime.datetime(2026, 9, 6, 8, 0).timestamp()
T1 = T0 + 3600
ROUTES_WATCHED = 5


def feed_rates(db=replay.DB):
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    fixes = con.execute("SELECT COUNT(*) FROM veh WHERE veh_ts BETWEEN ? AND ?",
                        (T0, T1)).fetchone()[0]
    per_min = np.array(con.execute(
        "SELECT COUNT(DISTINCT veh_id), COUNT(DISTINCT route_id) FROM veh "
        "WHERE veh_ts BETWEEN ? AND ? GROUP BY CAST(veh_ts/60 AS INT)",
        (T0, T1)).fetchall(), dtype=float)
    con.close()
    return fixes / (T1 - T0), np.median(per_min[:, 0]), np.median(per_min[:, 1])


def replays(net):
    """The same hour twice: predicting, and only tracking."""
    out = []
    for warmup in (0.0, 1e9):
        t = time.time()
        _, res = replay.run(net, t_from=T0, t_to=T1, warmup=warmup)
        out.append((time.time() - t, res))
    return out


def positions(res, net):
    """Where every tracked vehicle was believed to be at the last epoch, as
    lat/lon and route, which is what a map frame carries."""
    last = max(p[0] for p in res.pos)
    out = []
    for epoch, vi, ti, _, dist in res.pos:
        if epoch != last:
            continue
        trip = res.trip_ids[ti]
        shape = net.shapes.get(net.trip_shape.get(trip))
        if shape is None:
            continue
        x, y = shape.at(dist)
        out.append((vi, net.trip_route.get(trip, "?"),
                    y / network.KY + network.LAT0, x / network.KX + network.LON0))
    return out


def _grid(v, span=0.25):
    """Degrees onto the 16-bit city grid the packed frame uses."""
    a = np.asarray(v)
    return np.clip((a - a.min()) / span * 65535, 0, 65535).astype(np.uint16)


def payloads(rows):
    """Bytes on the wire for one map frame, JSON and packed, raw and gzipped.

    The packed form is what a real client would get: a vehicle is a 16-bit
    index, a position is two 16-bit offsets on a 20 km grid (0.3 m), a heading
    is one byte.
    """
    js = json.dumps([{"v": v, "r": r, "lat": round(lat, 5), "lon": round(lon, 5),
                      "b": (v * 37) % 360} for v, r, lat, lon in rows]).encode()
    packed = np.zeros(len(rows), dtype=np.dtype(
        [("v", "u2"), ("x", "u2"), ("y", "u2"), ("b", "u1"), ("f", "u1")]))
    packed["v"] = [v % 65536 for v, _, _, _ in rows]
    packed["x"] = _grid([lon for *_, lon in rows])
    packed["y"] = _grid([lat for _, _, lat, _ in rows])
    packed["b"] = [(v * 37) % 256 for v, _, _, _ in rows]
    return {"vehicles": len(rows),
            "json": len(js), "json_gz": len(gzip.compress(js, 6)),
            "packed": packed.nbytes,
            "packed_gz": len(gzip.compress(packed.tobytes(), 6))}


def main():
    fixes_s, vehicles, routes = feed_rates()
    print(f"peak hour {datetime.datetime.fromtimestamp(T0):%Y-%m-%d %H:%M}"
          f"-{datetime.datetime.fromtimestamp(T1):%H:%M}")
    print(f"  {vehicles:.0f} vehicles on {routes:.0f} routes at once, "
          f"{fixes_s:.1f} new fixes/s citywide")

    net = network.load()
    (t_pred, res), (t_track, _) = replays(net)
    epochs = res.epochs
    etas = res.buf.n / max(epochs, 1)
    print(f"  {epochs} epochs of {replay.EPOCH:.0f}s, "
          f"{len(res.pos) / max(epochs, 1):.0f} tracked vehicles and "
          f"{etas:.0f} stop ETAs per epoch")
    print(f"  replay {t_pred:.1f}s predicting, {t_track:.1f}s tracking only")
    print(f"  per epoch: {t_pred / epochs * 1000:.0f} ms total, of which "
          f"{(t_pred - t_track) / epochs * 1000:.0f} ms is prediction")
    print(f"  one core sustains {replay.EPOCH * epochs / t_pred:.0f}x real time")

    rows = positions(res, net)
    watched = sorted({r for _, r, _, _ in rows})[:ROUTES_WATCHED]
    for label, sel in (("whole city", rows),
                       (f"{ROUTES_WATCHED} routes",
                        [r for r in rows if r[1] in watched])):
        p = payloads(sel)
        print(f"  {label}: {p['vehicles']} vehicles, frame "
              f"{p['json'] / 1024:.1f} KiB json ({p['json_gz'] / 1024:.1f} gz), "
              f"{p['packed'] / 1024:.1f} KiB packed "
              f"({p['packed_gz'] / 1024:.1f} gz)")
        rate = fixes_s * p["vehicles"] / max(len(rows), 1)
        print(f"    at {rate:.1f} updates/s that is "
              f"{rate * p['json'] / max(p['vehicles'], 1):.0f} B/s json, "
              f"{rate * p['packed'] / max(p['vehicles'], 1):.0f} B/s packed, "
              f"per client")


if __name__ == "__main__":
    main()
