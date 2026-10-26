"""Door to door: ranked journeys of walk, ride, walk between two points.

Walking is measured on the footpath graph in `walk.py`, never as the crow flies.
Nothing bounds "close enough" by a radius: the bound is the time it would take to
walk the whole way, which is also offered as an option.

Each tracked vehicle enters the timetable as an extra trip whose stop times are
the live predictions, so a leg is "live" when the search picked one of those and
"scheduled" otherwise.

The search is one profile scan backwards from the door (`_Profile`): every hop
of every trip learns the soonest door arrival from riding it on. The options are
read off it at the stops the origin walks to, and each ride's backups - the
other ways to the door from where it boards - off the same scan at that stop,
so a backup is searched exactly as an option is.

The modules: `timetable`, `transfers` and `cache` hold the city; `tracked`
adds the vehicles being tracked; `hops` cuts the trips into the hops `scan`
reads; `ranking` picks the journeys offered; `search` runs it all and `cli`
tries one. Everything used outside the package is named here, so `plan.X`
keeps working.
"""
from .cache import load
from .cli import _clock, main
from .journey import CONFIDENCE, Aboard, Backup, Journey, Leg
from .ranking import NEAR_TIE
from .scan import (BACKUP_WINDOW, CHANGE_AHEAD, CHANGE_SLACK, GRACE, _Profile,
                   change_slack)
from .search import (DETOUR, FIRST_WALK, LONGEST_WALK, ROUNDS, WALK_CAPS,
                     _rushed, journeys)
# `Pattern` too: a timetable cached before the split names it as `plan.Pattern`
from .timetable import Pattern, Timetable, _seconds_since_midnight
from .tracked import (HORIZON_EDGE, QUIET_TRIPS, QUIET_WINDOW, LiveTrip,
                      live_trips, route_confidence)
from .transfers import DATA, TRANSFER_CAP, TRANSFERS, Transfers, build_transfers
