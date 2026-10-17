"""The server's half of the frame both clients decode in their own tests."""
import json
from pathlib import Path

import numpy as np
import pytest

from commuterlviv.live import state, wire

FRAME = json.loads((Path(__file__).parent / "wire_frame.json").read_text())

# Half a metre is the quantum, so equality is to seven decimal places
TOLERANCE = 1e-7


def _vehicles():
    rows = FRAME["vehicles"]
    veh = np.zeros(len(rows), state.VEH)
    for i, v in enumerate(rows):
        flags = (state.STALE if v["stale"] else 0) | (state.MOVING if v["moving"] else 0)
        veh[i] = (v["id"], v["route"], v["lat"], v["lon"], v["heading"], flags)
    return veh


def test_the_vehicles_encode_to_the_frame_the_clients_decode():
    frame = wire.encode(_vehicles(), FRAME["t"], FRAME["kind"], gone=FRAME["gone"])

    assert list(frame) == FRAME["bytes"]


def test_the_frame_decodes_to_the_positions_the_clients_expect():
    _, _, rows, _ = wire.decode(bytes(FRAME["bytes"]))

    lat, lon = wire.latlon(rows)

    assert lat == pytest.approx([d["lat"] for d in FRAME["decoded"]], abs=TOLERANCE)
    assert lon == pytest.approx([d["lon"] for d in FRAME["decoded"]], abs=TOLERANCE)
