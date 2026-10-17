"""Files written beside the one they replace and swapped in whole, so whoever
reads them - a running service, a search in flight - sees the old file or the
new one, never half of either."""
import contextlib
import os
from pathlib import Path


@contextlib.contextmanager
def replacing(path):
    """Where to write the new `path`: `<stem>.next<suffix>` beside it, so numpy
    keeps the name it is given. Swapped in when the block finishes and dropped
    if it raises, so a failed download or check keeps the file held."""
    path = Path(path)
    fresh = path.with_name(f"{path.stem}.next{path.suffix}")
    try:
        yield fresh
        os.replace(fresh, path)
    finally:
        fresh.unlink(missing_ok=True)
