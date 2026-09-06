"""One entry point for the six things this project does.

    collect     record the live feeds into data/feed.db, indefinitely
    evaluate    replay what was recorded and score every predictor on it
    experiment  score every switchable approach on the same recording
    sweep       vary one estimator constant and score every value of it
    check       take the model apart: is it the model, the tracking or the truth
    diag        ask what methodology the official API is actually using
"""
import argparse
import sys


def _collect(rest):
    from . import collect
    collect.main(rest)


def _evaluate(rest):
    from . import evaluate
    ap = argparse.ArgumentParser(prog="lvivpred evaluate")
    ap.add_argument("--warmup", type=float, default=0.0,
                    help="seconds of replay to learn from before scoring begins")
    ap.add_argument("--no-save", action="store_true",
                    help="do not write the learned model back to data/model.npz")
    a = ap.parse_args(rest)
    evaluate.main(warmup=a.warmup, save=not a.no_save)


def _when(s):
    """A local wall-clock time on the command line, as a unix timestamp."""
    import datetime
    try:
        return datetime.datetime.fromisoformat(s).timestamp()
    except ValueError:
        raise argparse.ArgumentTypeError(
            f"{s!r} is not a local time like 2026-09-06T07:00")


def _experiment(rest):
    from . import config, experiments
    ap = argparse.ArgumentParser(prog="lvivpred experiment")
    ap.add_argument("--warmup", type=float, default=1800.0,
                    help="seconds of replay to learn from before scoring begins")
    ap.add_argument("--from", dest="t_from", type=_when, metavar="TIME",
                    help="replay only from this local time, e.g. 2026-09-06T05:30")
    ap.add_argument("--to", dest="t_to", type=_when, metavar="TIME",
                    help="replay only up to this local time")
    ap.add_argument("--out", default=experiments.REPORTS, metavar="DIR",
                    help="where to write approaches.json and approaches.md")
    ap.add_argument("--only", nargs="+", metavar="NAME", choices=list(config.BY_NAME),
                    help=f"approaches to run (default all): {', '.join(config.BY_NAME)}")
    a = ap.parse_args(rest)
    variants = [config.BY_NAME[n] for n in a.only] if a.only else None
    kw = {} if a.t_to is None else {"t_to": a.t_to}
    experiments.run_all(variants=variants, warmup=a.warmup, out=a.out,
                        t_from=a.t_from, **kw)


def _sweep(rest):
    from . import config, sweep
    ap = argparse.ArgumentParser(prog="lvivpred sweep")
    ap.add_argument("field", choices=list(sweep.GRIDS),
                    help="the estimator constant to vary")
    ap.add_argument("values", nargs="*", type=float, metavar="VALUE",
                    help="values to try (default: the grid in sweep.py)")
    ap.add_argument("--base", default="full", choices=list(config.BY_NAME),
                    help="the approach to vary the constant on (default full)")
    ap.add_argument("--warmup", type=float, default=1800.0,
                    help="seconds of replay to learn from before scoring begins")
    ap.add_argument("--from", dest="t_from", type=_when, metavar="TIME")
    ap.add_argument("--to", dest="t_to", type=_when, metavar="TIME")
    a = ap.parse_args(rest)
    kw = {} if a.t_to is None else {"t_to": a.t_to}
    sweep.run(a.field, a.values or None, base=config.BY_NAME[a.base],
              warmup=a.warmup, t_from=a.t_from, **kw)


def _check(rest):
    from . import check
    _no_args("check", rest)
    check.report()


def _diag(rest):
    from . import diag
    _no_args("diag", rest)
    diag.main()


def _no_args(name, rest):
    if rest:
        raise SystemExit(f"lvivpred {name} takes no arguments, got {' '.join(rest)}")


COMMANDS = {"collect": _collect, "evaluate": _evaluate,
            "experiment": _experiment, "sweep": _sweep,
            "check": _check, "diag": _diag}


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if not argv or argv[0] not in COMMANDS:
        print(__doc__.strip())
        return 1 if argv else 0
    COMMANDS[argv[0]](argv[1:])
    return 0


if __name__ == "__main__":
    sys.exit(main())
