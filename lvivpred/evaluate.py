"""Run the replay and score every predictor against the same ground truth."""
from . import network, predictors, replay, score, state
from .truth import Truth


def main(net=None, save=True, **kw):
    net = net or network.load()
    model = replay.PaceModel(net)
    warm = state.load(model, net)
    model, res = replay.run(net, model=model, **kw)
    res.net = net

    truth = Truth(net, res)
    print(f"replay: {res.epochs} epochs, {res.buf.n} predictions, "
          f"{truth.n} crossings under {len(truth.by_trip_stop)} trip-and-stop "
          f"names and {len(truth.by_veh_stop)} vehicle-and-stop names"
          f"{'' if warm else '  (cold start: no usable snapshot)'}\n")

    score.report({"ours": predictors.ours(res, truth),
                  "api": predictors.api(res, truth),
                  "lad": predictors.lad(res, net, truth),
                  "schedule": predictors.schedule(res, truth, net)}, truth)
    if save:
        print("model state ->", state.save(model, net))
    return model, res, truth
