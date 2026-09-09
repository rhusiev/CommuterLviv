"""One entry point for the twelve things this project does.

    collect     record the live feeds into data/feed.db, indefinitely
    features    replay once and dump one feature row per prediction
    residual    fit offline models of what the shipped model gets wrong
    stack       blend the approaches that fail differently, per horizon
    evaluate    replay what was recorded and score every predictor on it
    experiment  score every switchable approach on the same recording
    sweep       vary one estimator constant and score every value of it
    check       take the model apart: is it the model, the tracking or the truth
    diag        ask what methodology the official API is actually using
    walk        fetch the city's footpaths once, for the journey planner
    plan        door to door: walk, ride, walk, ranked by arrival
    serve       run the live service: the model, over HTTP and websockets
    admin       mint invite links, list accounts, disable or delete one
"""
import argparse
import sys


def _collect(rest):
    from . import collect
    collect.main(rest)


def _features(rest):
    from . import features
    ap = argparse.ArgumentParser(prog="commuterlviv features")
    ap.add_argument("--out", default="reports/feats.npz", metavar="FILE")
    ap.add_argument("--warmup", type=float, default=0.0,
                    help="seconds of replay to learn from before rows are kept")
    ap.add_argument("--from", dest="t_from", type=_when, metavar="TIME")
    ap.add_argument("--to", dest="t_to", type=_when, metavar="TIME")
    a = ap.parse_args(rest)
    kw = {} if a.t_to is None else {"t_to": a.t_to}
    features.dump(a.out, warmup=a.warmup, t_from=a.t_from, **kw)


def _residual(rest):
    from . import residual
    ap = argparse.ArgumentParser(prog="commuterlviv residual")
    ap.add_argument("--feats", default="reports/feats.npz", metavar="FILE",
                    help="the feature table written by `commuterlviv features`")
    ap.add_argument("--fit-to", type=_when, metavar="TIME",
                    default=_when(residual.FIT_TO),
                    help=f"fit on rows emitted before this local time "
                         f"(default {residual.FIT_TO})")
    ap.add_argument("--test-from", type=_when, metavar="TIME",
                    default=_when(residual.TEST_FROM),
                    help=f"score on rows emitted from this local time "
                         f"(default {residual.TEST_FROM})")
    ap.add_argument("--quick", action="store_true",
                    help="skip the slow models and the ablation")
    ap.add_argument("--out", default=residual.REPORTS, metavar="DIR")
    ap.add_argument("--label", default="", metavar="NAME",
                    help="suffix for the report, so two splits can coexist")
    a = ap.parse_args(rest)
    residual.main(feats=a.feats, fit_to=a.fit_to, test_from=a.test_from,
                  quick=a.quick, out=a.out, label=a.label)


def _stack(rest):
    from . import config, residual, stack
    ap = argparse.ArgumentParser(prog="commuterlviv stack")
    ap.add_argument("--members", nargs="+", metavar="NAME",
                    choices=list(config.BY_NAME), default=list(stack.MEMBERS),
                    help="approaches to blend; `api` is always added")
    ap.add_argument("--fit-to", type=_when, metavar="TIME",
                    default=_when(residual.FIT_TO),
                    help=f"fit weights on predictions emitted before this local "
                         f"time (default {residual.FIT_TO})")
    ap.add_argument("--test-from", type=_when, metavar="TIME",
                    default=_when(residual.TEST_FROM),
                    help=f"score on predictions emitted from this local time "
                         f"(default {residual.TEST_FROM})")
    ap.add_argument("--feats", default="reports/feats.npz", metavar="FILE",
                    help="the feature table, for the full + residual hybrid")
    ap.add_argument("--from", dest="t_from", type=_when, metavar="TIME")
    ap.add_argument("--to", dest="t_to", type=_when, metavar="TIME")
    ap.add_argument("--out", default=stack.REPORTS, metavar="DIR")
    ap.add_argument("--label", default="", metavar="NAME",
                    help="suffix for the report, so two splits can coexist")
    a = ap.parse_args(rest)
    kw = {} if a.t_to is None else {"t_to": a.t_to}
    stack.main(members=tuple(a.members), fit_to=a.fit_to, test_from=a.test_from,
               feats=a.feats, out=a.out, label=a.label, t_from=a.t_from, **kw)


def _evaluate(rest):
    from . import evaluate
    ap = argparse.ArgumentParser(prog="commuterlviv evaluate")
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
    ap = argparse.ArgumentParser(prog="commuterlviv experiment")
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
    ap = argparse.ArgumentParser(prog="commuterlviv sweep")
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


def _walk(rest):
    from . import walk
    walk.main(rest)


def _plan(rest):
    from . import plan
    plan.main(rest)


def _serve(rest):
    import uvicorn
    from .live import app as live_app
    ap = argparse.ArgumentParser(prog="commuterlviv serve")
    ap.add_argument("--host", default="127.0.0.1",
                    help="bind address; leave it on loopback behind a proxy")
    ap.add_argument("--port", type=int, default=8080)
    a = ap.parse_args(rest)
    # The hub sends its own idle frame, and the client's address is read from
    # X-Forwarded-For only where the deployment says so - not by uvicorn.
    # A client message is a filter of at most a few hundred bytes, so the
    # 16 MB frame uvicorn would otherwise accept is refused at the protocol
    # instead of being read into memory first
    uvicorn.run(live_app.build(), host=a.host, port=a.port,
                ws_ping_interval=None, access_log=False, proxy_headers=False,
                ws_max_size=live_app.hub.MAX_MSG * 4)


def _admin(rest):
    from .live import admin
    ap = argparse.ArgumentParser(prog="commuterlviv admin")
    sub = ap.add_subparsers(dest="what", required=True)
    inv = sub.add_parser("invite", help="mint a registration link, printed once")
    inv.add_argument("--uses", type=int, default=1)
    inv.add_argument("--days", type=int, default=30)
    inv.add_argument("--note", default=None)
    sub.add_parser("users", help="list accounts")
    off = sub.add_parser("disable", help="lock an account and end its sessions")
    off.add_argument("username")
    off.add_argument("--undo", action="store_true")
    gone = sub.add_parser("delete", help="erase an account and all its data")
    gone.add_argument("username")
    gone.add_argument("--yes", action="store_true",
                      help="required: there is no undo")
    a = ap.parse_args(rest)
    if a.what == "invite":
        print(admin.run(admin.invite(a.uses, a.days, a.note)))
    elif a.what == "users":
        for r in admin.run(admin.users()):
            print(f"{r['username']:<20} joined {r['created_at']:%Y-%m-%d}  "
                  f"last login {r['last_login'] or '-'}  "
                  f"sessions {r['sessions']}"
                  f"{'  DISABLED' if r['disabled'] else ''}")
    elif a.what == "delete":
        if not a.yes:
            raise SystemExit("pass --yes: deleting an account cannot be undone")
        ok = admin.run(admin.delete(a.username))
        print("done" if ok else "no such user")
    else:
        ok = admin.run(admin.disable(a.username, not a.undo))
        print("done" if ok else "no such user")


def _no_args(name, rest):
    if rest:
        raise SystemExit(f"commuterlviv {name} takes no arguments, got {' '.join(rest)}")


COMMANDS = {"collect": _collect, "features": _features, "residual": _residual,
            "stack": _stack, "evaluate": _evaluate, "experiment": _experiment,
            "sweep": _sweep, "check": _check, "diag": _diag,
            "walk": _walk, "plan": _plan, "serve": _serve, "admin": _admin}


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if not argv or argv[0] not in COMMANDS:
        print(__doc__.strip())
        return 1 if argv else 0
    COMMANDS[argv[0]](argv[1:])
    return 0


if __name__ == "__main__":
    sys.exit(main())
