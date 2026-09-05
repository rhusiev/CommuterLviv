"""The approaches, as a set of switches.

Every design decision in the model is a claim that something is worth doing.
Each switch here turns one of them off, so the claim can be checked against the
same recording rather than argued about. `full` is the model as shipped; every
other variant differs from it in exactly one place, except the last two, which
replace the prediction step rather than the learning.

Run them with `python3 -m lvivpred experiment`.
"""
from dataclasses import dataclass, replace


@dataclass(frozen=True)
class Config:
    name: str
    doc: str
    prior: bool = True          # learn a multiplier on timetabled pace, not pace
    hold: bool = True           # count standing time separately from rolling
    corridor: bool = True       # pool evidence across routes sharing a street
    fast: bool = True           # keep a short half-life term for live traffic
    incremental: bool = True    # report a cell crossing while it is in progress
    unit: str = "cell"          # what a travel time is learned per: cell|section
    vehicle_offset: bool = False   # scale the ETA by how this vehicle is running
    eta: str = "model"          # how a prediction is formed: model|lateness


FULL = Config("full", "The model as it ships: everything below turned on.")

VARIANTS = [
    FULL,
    replace(FULL, name="no-prior", prior=False,
            doc="Learn pace itself instead of a multiplier on the timetable's. "
                "Costs the model everything the schedule knows about where and "
                "when the city is slow, so every cell must be learned from live "
                "data alone."),
    replace(FULL, name="no-hold", hold=False,
            doc="One quantity instead of two: standing time is folded into pace "
                "and scales with distance. This is what a speed-per-section "
                "model does implicitly."),
    replace(FULL, name="no-corridor", corridor=False,
            doc="A cell backs off straight to one city-wide number, never to the "
                "street it is on. Tests whether pooling across routes that "
                "share a road is worth anything."),
    replace(FULL, name="no-fast", fast=False,
            doc="Only the 5400 s half-life term. The model still knows this "
                "street, but not what traffic is doing on it right now."),
    replace(FULL, name="no-incremental", incremental=False,
            doc="A crossing is reported only once finished. Fast crossings then "
                "report before slow ones, so the model hears about a jam after "
                "it has cleared."),
    replace(FULL, name="sections", unit="section", corridor=False,
            doc="Learn one travel time per stop-to-stop section rather than per "
                "100 m cell. Corridor pooling is off because a section spans "
                "many corridors and cannot be assigned to one."),
    replace(FULL, name="vehicle-offset", vehicle_offset=True,
            doc="The full road model, then scaled by how fast this particular "
                "vehicle has been running against it. Asks whether anything is "
                "left in the vehicle after the road is accounted for."),
    Config("schedule-offset",
           "Not a road model at all: the timetable plus this vehicle's current "
           "lateness, held constant to the end of the trip. This is what the "
           "official API was measured to be doing, reimplemented here so it can "
           "be scored on exactly the same events.",
           eta="lateness"),
]

BY_NAME = {c.name: c for c in VARIANTS}
