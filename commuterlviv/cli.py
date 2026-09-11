"""One entry point for the five things this project does.

    collect     record the live feeds into data/feed.db, indefinitely
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
    # client messages are tiny, so cap the frame size uvicorn will buffer;
    # the hub sends its own keepalive, hence ws_ping_interval=None
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
    op = sub.add_parser("operator", help="let an account read /api/status")
    op.add_argument("username")
    op.add_argument("--undo", action="store_true")
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
                  f"{'  DISABLED' if r['disabled'] else ''}"
                  f"{'  OPERATOR' if r['operator'] else ''}")
    elif a.what == "operator":
        ok = admin.run(admin.operator(a.username, not a.undo))
        print("done" if ok else "no such user")
    elif a.what == "delete":
        if not a.yes:
            raise SystemExit("pass --yes: deleting an account cannot be undone")
        ok = admin.run(admin.delete(a.username))
        print("done" if ok else "no such user")
    else:
        ok = admin.run(admin.disable(a.username, not a.undo))
        print("done" if ok else "no such user")


COMMANDS = {"collect": _collect, "walk": _walk, "plan": _plan,
            "serve": _serve, "admin": _admin}


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if not argv or argv[0] not in COMMANDS:
        print(__doc__.strip())
        return 1 if argv else 0
    COMMANDS[argv[0]](argv[1:])
    return 0


if __name__ == "__main__":
    sys.exit(main())
