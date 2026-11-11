"""The style a deployment serves: this site's URLs, with the basemap's
generation on the ones a client caches for weeks."""
import json
import pathlib
import subprocess

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "deploy" / "style.sh"
PUBLIC = "https://tiles.versatiles.org"
SITE = "https://example.test/tiles"
GENERATION = "1762800000"

STYLE = {
    "version": 8,
    "sprite": [{"id": "base", "url": f"{PUBLIC}/assets/sprites/base"}],
    "glyphs": f"{PUBLIC}/assets/glyphs/{{fontstack}}/{{range}}.pbf",
    "sources": {
        "osm": {"type": "vector",
                "tiles": [f"{PUBLIC}/tiles/osm/{{z}}/{{x}}/{{y}}"]},
        "landcover": {"type": "vector",
                      "tiles": [f"{PUBLIC}/tiles/landcover-vectors/{{z}}/{{x}}/{{y}}"]},
    },
    "layers": [],
}


def _rewritten() -> dict:
    out = subprocess.run(
        ["sh", str(SCRIPT), SITE, GENERATION],
        input=json.dumps(STYLE), capture_output=True, text=True, check=True,
    ).stdout
    return json.loads(out)


def test_every_source_names_this_site_and_the_generation() -> None:
    style = _rewritten()

    assert style["sources"]["osm"]["tiles"] == [
        f"{SITE}/tiles/osm/{{z}}/{{x}}/{{y}}?v={GENERATION}"]
    assert style["sources"]["landcover"]["tiles"] == [
        f"{SITE}/tiles/landcover-vectors/{{z}}/{{x}}/{{y}}?v={GENERATION}"]


def test_glyphs_carry_the_generation_and_sprites_do_not() -> None:
    style = _rewritten()

    assert style["glyphs"] == f"{SITE}/assets/glyphs/{{fontstack}}/{{range}}.pbf?v={GENERATION}"
    # the phone's tile reader appends ".json" to the whole URL, query included
    assert style["sprite"][0]["url"] == f"{SITE}/assets/sprites/base"
