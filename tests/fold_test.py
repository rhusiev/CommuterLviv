"""The reference for how both clients fold names before matching them.

The web folds with Unicode's NFKD, which Dart lacks, so the app writes the same
folding out by hand. `tests/fold_cases.json` holds what NFKD folds every Latin
and Cyrillic letter to, and both clients' tests check themselves against it.
This test keeps the file equal to NFKD; `python3 -m tests.fold_test` rewrites it.
"""
import json
import unicodedata
from pathlib import Path

CASES = Path(__file__).parent / "fold_cases.json"
APOSTROPHES = "'ʼ’"
MARKS = range(0x300, 0x370)     # Combining Diacritical Marks
# Basic Latin, Latin-1 Supplement and Latin Extended-A, and Cyrillic
BLOCKS = [range(0x20, 0x7F), range(0xA0, 0x180), range(0x400, 0x500)]


def fold(s):
    """Lower case, NFKD, and the marks and apostrophes dropped."""
    s = unicodedata.normalize("NFKD", s.lower())
    return "".join(c for c in s if ord(c) not in MARKS and c not in APOSTROPHES)


def cases():
    """Every letter of `BLOCKS`, the apostrophes and one letter typed with its
    mark apart, each beside what it folds to."""
    letters = [chr(i) for block in BLOCKS for i in block
               if unicodedata.category(chr(i)).startswith("L")]
    return [[c, fold(c)] for c in [*letters, *APOSTROPHES, "й"]]


def test_the_shared_cases_are_what_nfkd_folds_to():
    held = json.loads(CASES.read_text())["cases"]

    assert held == cases(), "rewrite it with `python3 -m tests.fold_test`"


if __name__ == "__main__":
    rows = ",\n".join(f"  {json.dumps(c, ensure_ascii=False)}" for c in cases())
    about = ("Each name fragment beside what both clients fold it to before "
             "matching; written by `python3 -m tests.fold_test`")
    CASES.write_text(f'{{"about": {json.dumps(about)},\n "cases": [\n{rows}\n]}}\n')
