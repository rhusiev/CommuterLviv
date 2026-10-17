"""The newest rows of a learner's training data, in one preallocated array."""
import numpy as np


class Ring:
    """The last `size` rows of `width` numbers ever added."""

    def __init__(self, size, width):
        self._rows = np.zeros((size, width), dtype=np.float32)
        self._wrote = 0      # rows ever added

    @property
    def width(self):
        return self._rows.shape[1]

    def add(self, row):
        self._rows[self._wrote % len(self._rows)] = row
        self._wrote += 1

    def oldest_first(self):
        """A copy of the rows kept, oldest first."""
        size = len(self._rows)
        if self._wrote < size:
            return self._rows[:self._wrote].copy()
        at = self._wrote % size
        return np.concatenate([self._rows[at:], self._rows[:at]])

    def put_before(self, rows):
        """Take `rows` as older than any added so far, keeping the newest."""
        rows = np.concatenate([rows, self.oldest_first()])[-len(self._rows):]
        self._rows[:len(rows)] = rows
        self._wrote = len(rows)
