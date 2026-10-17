import pytest

from commuterlviv import files


def test_the_new_file_is_swapped_in_once_written(tmp_path):
    path = tmp_path / "held.npz"
    path.write_text("old")

    with files.replacing(path) as fresh:
        fresh.write_text("new")
        assert path.read_text() == "old"

    assert path.read_text() == "new"
    assert sorted(p.name for p in tmp_path.iterdir()) == ["held.npz"]


def test_a_failed_write_keeps_the_held_file_and_leaves_nothing_beside_it(tmp_path):
    path = tmp_path / "held.npz"
    path.write_text("old")

    with pytest.raises(ValueError), files.replacing(path) as fresh:
        fresh.write_text("half")
        raise ValueError("refused")

    assert path.read_text() == "old"
    assert sorted(p.name for p in tmp_path.iterdir()) == ["held.npz"]
