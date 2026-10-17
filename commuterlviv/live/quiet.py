"""Whether the vehicles have gone quiet while the timetable has the city running.

In Lviv the vehicles stop reporting where they are during an air raid alert, and
the map empties while the buses still run. That is not the only cause - the feed
itself can fail - so the clients word it as a possibility. At night the
timetable has next to nothing under way, and a quiet feed then means nothing.

Measured on the recording, 2026-09-13 to 09-17 in 10-minute samples: in normal
service a vehicle reported within `replay.STALE` for 0.83-1.2 of the trips the
timetable had under way; in four blackouts for 0.00-0.21, and 0.40-0.43 at their
edges. Night had fewer than 50 trips under way.
"""
import numpy as np

from .. import plan

# Both chosen, not derived: the measured shares above leave a wide gap
MIN_RUNNING = 50     # trips under way below which nothing is judged
QUIET_SHARE = 0.5    # of them reporting, under which the vehicles are quiet


def running(tt, now):
    """How many trips the timetable `tt` has between leaving their first stop
    and reaching their last at `now`, unix seconds."""
    at, midnight = plan._seconds_since_midnight(now)
    day = tt.on(midnight)
    return sum(int(np.count_nonzero((p.times[:, 0] <= at)
                                    & (p.times[:, -1] >= at)))
               for p in day.patterns)


def judge(reporting, tt, now):
    """Whether `reporting` vehicles are too few for the trips `tt` has under
    way at `now`; never without a timetable."""
    if tt is None:
        return False
    under_way = running(tt, now)
    return under_way >= MIN_RUNNING and reporting < QUIET_SHARE * under_way
