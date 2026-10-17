"""One line per event on stdout, stamped with the local time."""
import time

EXC_CHARS = 200     # an exception's repr is cut to this, so one cannot flood the log


def log(*a):
    """Print `a` after the time, flushed so the container's log is current."""
    print(time.strftime("%Y-%m-%d %H:%M:%S"), *a, flush=True)


def brief(exc):
    """The start of `exc`'s repr - enough to tell one failure from another."""
    return repr(exc)[:EXC_CHARS]
