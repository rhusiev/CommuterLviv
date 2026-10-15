/// Stop names matched the way people type them: words in any order, each a
/// prefix of some word of the name, one slip allowed in a word of four letters
/// or more. "шевч пл" finds "Площа Шевченка", "стрийска" finds "Стрийська".
library;

import 'dart:math' show min;

import 'models.dart';

/// Letters typed before a query is looked up at all: below this every prefix
/// matches half the city.
const minTyped = 2;

final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// What Unicode decomposition would fold, by hand: Dart has no NFKD.
const _folded = {'й': 'и', 'ї': 'і', 'ё': 'е', "'": '', 'ʼ': '', '’': ''};

List<String> words(String s) {
  final folded = s.toLowerCase().split('').map((c) => _folded[c] ?? c).join();
  return [for (final m in _word.allMatches(folded)) m[0]!];
}

/// Fewest edits turning [q] into some prefix of [w].
int _prefixEdits(String q, String w) {
  var row = List.generate(w.length + 1, (j) => j);
  for (var i = 1; i <= q.length; i++) {
    final next = [i];
    for (var j = 1; j <= w.length; j++) {
      next.add(
        min(
          min(row[j] + 1, next[j - 1] + 1),
          row[j - 1] + (q[i - 1] == w[j - 1] ? 0 : 1),
        ),
      );
    }
    row = next;
  }
  return row.reduce(min);
}

int _wordScore(String q, List<String> name) {
  var best = 0;
  for (final w in name) {
    if (w.startsWith(q)) return 3;
    if (q.length >= 3 && w.contains(q)) {
      best = 2;
    } else if (q.length >= 4 && best < 1 && _prefixEdits(q, w) <= 1) {
      best = 1;
    }
  }
  return best;
}

/// How well a name's [words] answer the query's; 0 is not at all.
int score(List<String> query, List<String> name) {
  var total = 0;
  for (final q in query) {
    final s = _wordScore(q, name);
    if (s == 0) return 0;
    total += s;
  }
  return total;
}

/// The saved [places] whose names answer [query], best first and shorter names
/// first among equals, as stops are ranked.
List<Place> matching(List<Place> places, String query) {
  final q = words(query);
  if (q.join().length < minTyped) return const [];
  final scored = [
    for (final p in places)
      if (score(q, words(p.name)) case final s when s > 0) (s, p),
  ];
  scored.sort(
    (a, b) => a.$1 != b.$1 ? b.$1 - a.$1 : a.$2.name.length - b.$2.name.length,
  );
  return [for (final (_, p) in scored) p];
}
