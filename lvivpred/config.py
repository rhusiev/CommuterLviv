"""The approaches, as a set of switches.

Every design decision in the model is a claim that something is worth doing.
Each switch here turns one of them off, so the claim can be checked against the
same recording rather than argued about. `full` is the model as shipped; most
other variants differ from it in exactly one place. Three replace the learning
outright with an estimator from `baselines.py`, and the last replaces the
prediction step instead.

Run them with `python3 -m lvivpred experiment`.
"""
from dataclasses import dataclass, replace


@dataclass(frozen=True)
class Config:
    name: str
    doc: str
    prior: str = "level"        # use of the timetable's pace: level|shape|off
    hold: bool = True           # count standing time separately from rolling
    corridor: bool = True       # pool evidence across routes sharing a street
    fast: bool = True           # keep a short half-life term for live traffic
    incremental: bool = True    # report a cell crossing while it is in progress
    unit: str = "cell"          # what a travel time is learned per: cell|section
    vehicle_offset: str = "off"    # scale the ETA by this vehicle: off|flat|decay
    eta: str = "model"          # how a prediction is formed: model|lateness
    learn: str = "online"       # what does the learning: online|table|table-live|knn
    knn: int = 10               # crossings the knn estimator keeps per unit

    # Shrinkage: observations a layer needs before it outweighs the one it backs
    # off to. Half-lives: how live "now" is, and how long the baseline remembers.
    k_unit: float = 4.0
    k_corr: float = 4.0
    fast_hl: float = 480.0
    slow_hl: float = 5400.0


FULL = Config("full", "The model as it ships: everything below turned on.")

VARIANTS = [
    FULL,
    replace(FULL, name="no-prior", prior="off",
            doc="Learn pace itself instead of a multiplier on the timetable's. "
                "Costs the model everything the schedule knows about where and "
                "when the city is slow, so every cell must be learned from live "
                "data alone."),
    replace(FULL, name="prior-shape", prior="shape",
            doc="Keep the timetable as a shape but not as a level: the same "
                "relative map of where and when the city is slow, rescaled so "
                "its own average pace is a constant and the level is learned "
                "like `no-prior` learns it. Tests whether the prior's measured "
                "6% slow bias is the whole of what it costs."),
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
    replace(FULL, name="k-split", k_unit=16.0, k_corr=1.0,
            doc="One shrinkage constant for both layers is measured to be the "
                "wrong shape: a cell is crossed 11.5 times a day and its fast "
                "term supplies 8% of the blend, while a corridor has ten times "
                "the evidence and is shrunk just as hard. This trusts the "
                "corridor sooner and the cell later."),
    replace(FULL, name="sections", unit="section", corridor=False,
            doc="Learn one travel time per stop-to-stop section rather than per "
                "100 m cell. Corridor pooling is off because a section spans "
                "many corridors and cannot be assigned to one."),
    replace(FULL, name="sections-no-prior", unit="section", corridor=False,
            prior="off",
            doc="Sections and no timetable prior together. Each alone beats the "
                "full model, and the measured reason is the same one - the "
                "prior's bias reaches a cell only where live evidence is thin - "
                "so the two gains may well be the same gain counted twice."),
    replace(FULL, name="vehicle-offset", vehicle_offset="flat",
            doc="The full road model, then scaled by how fast this particular "
                "vehicle has been running against it. Asks whether anything is "
                "left in the vehicle after the road is accounted for."),
    replace(FULL, name="offset-decay", vehicle_offset="decay",
            doc="The same vehicle correction, but faded out along the path "
                "instead of applied flat. A vehicle's speed ratio is measured "
                "to persist about 4.5 minutes, so each leg of the trip is "
                "corrected only by what is left of that ratio by the time the "
                "vehicle gets there."),
    replace(FULL, name="table", learn="table", unit="section", corridor=False,
            doc="No online learning at all: one pace and one hold per section "
                "per hour of the day, fitted during the warmup and then frozen. "
                "The historical average every transit paper starts from. What "
                "separates it from `full` is the whole value of learning as "
                "fixes arrive - so run it with a warmup that is a real training "
                "window, an evening scored the next morning."),
    replace(FULL, name="table-live", learn="table-live", unit="section",
            corridor=False,
            doc="The frozen table times one online number: how fast today is "
                "running against it, city-wide. One parameter of live learning "
                "instead of tens of thousands, so what separates it from "
                "`table` is the value of knowing today is slow and nothing "
                "else."),
    replace(FULL, name="knn", learn="knn", unit="section", corridor=False,
            doc="The median of the last 10 crossings of this section by any "
                "vehicle, with no corridor, no global fallback and no "
                "half-life. Tests the back-off hierarchy against a plain "
                "recency window, and the mean against the median - MAE is "
                "minimised by the median, which nothing else here uses."),
    Config("schedule-offset",
           "Not a road model at all: the timetable plus this vehicle's current "
           "lateness, held constant to the end of the trip. This is what the "
           "official API was measured to be doing, reimplemented here so it can "
           "be scored on exactly the same events.",
           eta="lateness"),
]

BY_NAME = {c.name: c for c in VARIANTS}
