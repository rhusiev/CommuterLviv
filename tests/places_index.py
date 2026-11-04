"""A place search index of a few made-up places, in the format osm-mapidx's
builder writes and `commuterlviv.mapidx` reads."""
import sqlite3
from dataclasses import dataclass

from commuterlviv.mapidx.translit import normalise, number_key
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
CREATE TABLE streets(
  rowid INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  words TEXT NOT NULL
);
CREATE TABLE addresses(
  street_id INTEGER NOT NULL REFERENCES streets(rowid),
  number_key TEXT NOT NULL,
  number TEXT NOT NULL,
  place TEXT NOT NULL,
  lon REAL NOT NULL,
  lat REAL NOT NULL
);
CREATE UNIQUE INDEX addresses_at ON addresses(street_id, number_key, place);
"""


@dataclass
class Place:
    name: str
    lat: float
    lon: float
    context: tuple[str, ...] = ()
    category: str = "amenity=cafe"


@dataclass
class House:
    """A house number as the builder tags it: the street it sits on, the number
    as mapped, and the settlement that tells two streets of one name apart."""
    street: str
    number: str
    place: str
    lat: float
    lon: float


def write(path, places, houses=()):
    """The index of `places` and `houses`, place row ids in their order, at `path`."""
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
        _write_houses(db, houses)
    db.close()
    return path


def _write_houses(db, houses):
    """Street ids in the order their names first appear, as emit numbers them."""
    ids: dict[str, int] = {}
    for house in houses:
        street_id = ids.get(house.street)
        if street_id is None:
            street_id = ids[house.street] = len(ids) + 1
            db.execute("INSERT INTO streets VALUES (?,?,?)",
                       (street_id, house.street,
                        " ".join(sorted(words(normalise(house.street))))))
        db.execute("INSERT INTO addresses VALUES (?,?,?,?,?,?)",
                   (street_id, number_key(house.number), house.number,
                    house.place, house.lon, house.lat))
