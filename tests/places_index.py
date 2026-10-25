"""A place search index of a few made-up places, in the format osm-mapidx's
builder writes and `commuterlviv.mapidx` reads."""
import sqlite3
from dataclasses import dataclass

from commuterlviv.mapidx.translit import normalise
from commuterlviv.mapidx.vocab import NAME_BIT, encode, words

SCHEMA = """
CREATE TABLE places(
  rowid INTEGER PRIMARY KEY,
  lon REAL NOT NULL,
  lat REAL NOT NULL,
  display_name TEXT NOT NULL,
  category TEXT NOT NULL,
  name_terms TEXT NOT NULL,
  context_terms TEXT NOT NULL
);
CREATE TABLE vocab(word TEXT PRIMARY KEY, places INTEGER NOT NULL,
                   postings BLOB NOT NULL) WITHOUT ROWID;
CREATE VIRTUAL TABLE vocab_fuzzy USING fts5(word, tokenize='trigram');
"""


@dataclass
class Place:
    name: str
    lat: float
    lon: float
    context: tuple[str, ...] = ()
    category: str = "amenity=cafe"


def write(path, places):
    """The index of `places`, row ids in their order, at `path`."""
    postings: dict[str, list[int]] = {}
    rows = []
    for rowid, place in enumerate(places, 1):
        name = words(normalise(place.name))
        context = words(normalise(" ".join(place.context))) - name
        for word in name:
            postings.setdefault(word, []).append(rowid << 1 | NAME_BIT)
        for word in context:
            postings.setdefault(word, []).append(rowid << 1)
        shown = (f"{place.name} ({', '.join(place.context)})" if place.context
                 else place.name)
        rows.append((rowid, place.lon, place.lat, shown, place.category,
                     " ".join(sorted(name)), " ".join(sorted(context))))
    with sqlite3.connect(path) as db:
        db.executescript(SCHEMA)
        db.executemany("INSERT INTO places VALUES (?,?,?,?,?,?,?)", rows)
        for word, refs in sorted(postings.items()):
            db.execute("INSERT INTO vocab VALUES (?,?,?)", (word, len(refs), encode(refs)))
            db.execute("INSERT INTO vocab_fuzzy(word) VALUES (?)", (word,))
    db.close()
    return path
