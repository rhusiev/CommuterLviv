"""Is `tuned` just `no-prior` reached by a different route?

`tuned` keeps the timetable prior and scores a bias of -66 s; `no-prior` deletes
it and scores -63; the two match to within a second in five of six horizon
buckets. The hypothesis is that less shrinkage and longer memory let the learned
pace dominate the prior, so the prior stops mattering. If so, turning the prior
off *on top of* the tuned constants should change almost nothing.

It does. Deleting the prior costs `full` 2 s of MAE at 0-1 min and 13 s at
10-20; it costs `tuned` 0 s and 2 s. The two results are one result.
"""
from dataclasses import replace
from commuterlviv import config, network, replay, score
from commuterlviv.experiments import _end

net = network.load()
tuned = next(c for c in config.VARIANTS if c.name == "tuned")
cfgs = [config.FULL, tuned,
        replace(tuned, name="tuned-no-prior", prior="off"),
        next(c for c in config.VARIANTS if c.name == "no-prior")]
named, truth, rec = replay.run_many(net, cfgs, db=replay.DB, t_to=_end(replay.DB))
paired = score.common(named)
score.table(paired, truth, ci=True)
