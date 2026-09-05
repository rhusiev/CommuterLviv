"""One entry point for the four things this project does.

    collect    record the live feeds into data/feed.db, indefinitely
    evaluate   replay what was recorded and score every predictor on it
    check      take the model apart: is it the model, the tracking or the truth
    diag       ask what methodology the official API is actually using
"""
import argparse
import sys


def _collect(rest):
    from . import collect
    sys.argv = ["collect"] + rest
    collect.main()


def _evaluate(rest):
    from . import evaluate
    ap = argparse.ArgumentParser(prog="lvivpred evaluate")
    ap.add_argument("--warmup", type=float, default=0.0,
                    help="seconds of replay to learn from before scoring begins")
    ap.add_argument("--no-save", action="store_true",
                    help="do not write the learned model back to data/model.npz")
    a = ap.parse_args(rest)
    evaluate.main(warmup=a.warmup, save=not a.no_save)


def _check(rest):
    from . import check
    check.report()


def _diag(rest):
    from . import diag
    diag.main()


COMMANDS = {"collect": _collect, "evaluate": _evaluate,
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
