"""The model's approaches as switches: each variant differs from `full` in one
place. The service runs the one `COMMUTERLVIV_VARIANT` names, and
`replay.run(cfg=...)` scores any of them offline."""
from dataclasses import dataclass, replace


@dataclass(frozen=True)
class Config:
    name: str
    doc: str
    prior: str = "level"        # use of the timetable's pace: level|shape
    incremental: bool = True    # report a cell crossing while it is in progress

    # k_*: observations a layer needs before it outweighs the layer it backs off
    # to. *_hl: half-lives, in seconds. `prof_hl` is not a term but a back-off
    # target, 0.0 for none: one number per cell per hour of the day.
    k_unit: float = 4.0
    k_corr: float = 4.0
    fast_hl: float = 480.0
    slow_hl: float = 5400.0
    prof_hl: float = 0.0


FULL = Config("full", "Every switch below turned on, and no hour-of-day profile.")

# Each is cheaper than `profile`, the one served, and within 5% of its mean
# error at every horizon (docs/how-it-works.md, "Cheaper variants")
VARIANTS = [
    FULL,
    replace(FULL, name="prior-shape", prior="shape",
            doc="Keep the timetable as a shape but not as a level: the same "
                "relative map of where and when the city is slow, rescaled so "
                "its own average pace is a constant and the level is learned. "
                "Tests whether the prior's measured 6% slow bias is the whole "
                "of what it costs."),
    replace(FULL, name="no-incremental", incremental=False,
            doc="A crossing is reported only once finished. Fast crossings then "
                "report before slow ones, so the model hears about a jam after "
                "it has cleared."),
    replace(FULL, name="profile", prof_hl=604800.0,
            doc="What this cell does at this hour, learned across days and kept "
                "for weeks, put where the corridor used to be: the thing the "
                "live terms fall back on when they have nothing. Finding 6 "
                "measures the model opening the morning peak believing the city "
                "15% slower than it is, because the overnight gap decays every "
                "live term away and leaves only the timetable. This carries "
                "yesterday's morning into this morning."),
]

BY_NAME = {c.name: c for c in VARIANTS}
