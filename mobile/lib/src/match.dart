/// Stop names matched the way people type them: words in any order, each a
/// prefix of some word of the name, one slip allowed in a word of four letters
/// or more. "шевч пл" finds "Площа Шевченка", "стрийска" finds "Стрийська".
library;

import 'dart:math' show max, min;

import 'models.dart';

/// Letters typed before a query is looked up at all: below this every prefix
/// matches half the city.
const minTyped = 2;

final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// What the web's NFKD does to a Latin or Cyrillic letter, written out: Dart
/// has no NFKD. Each key is what the letters after it fold to;
/// `tests/fold_cases.json` holds the cases both clients are checked against.
const _foldsTo = {
  'a': 'ªàáâãäåāăą',
  'c': 'çćĉċč',
  'd': 'ď',
  'e': 'èéêëēĕėęě',
  'g': 'ĝğġģ',
  'h': 'ĥ',
  'i': 'ìíîïĩīĭį',
  'ij': 'ĳ',
  'j': 'ĵ',
  'k': 'ķ',
  'l': 'ĺļľ',
  'l·': 'ŀ',
  'n': 'ñńņňŉ',
  'o': 'ºòóôõöōŏő',
  'r': 'ŕŗř',
  's': 'śŝşšſ',
  't': 'ţť',
  'u': 'ùúûüũūŭůűų',
  'w': 'ŵ',
  'y': 'ýÿŷ',
  'z': 'źżž',
  'μ': 'µ',
  'а': 'ӑӓ',
  'г': 'ѓ',
  'е': 'ѐёӗ',
  'ж': 'ӂӝ',
  'з': 'ӟ',
  'и': 'йѝӣӥ',
  'к': 'ќ',
  'о': 'ӧ',
  'у': 'ўӯӱӳ',
  'ч': 'ӵ',
  'ы': 'ӹ',
  'э': 'ӭ',
  'і': 'ї',
  'ѵ': 'ѷ',
  'ә': 'ӛ',
  'ө': 'ӫ',
  '': "'ʼ’",
};

final _folds = {
  for (final e in _foldsTo.entries)
    for (final c in e.value.split('')) c: e.key,
};

/// Combining marks, typed apart from their letter.
final _marks = RegExp('[\u0300-\u036f]');

/// Case, accents and apostrophes gone, so й matches и and ʼ is not typed.
String fold(String s) => s
    .toLowerCase()
    .replaceAll(_marks, '')
    .split('')
    .map((c) => _folds[c] ?? c)
    .join();

List<String> words(String s) => [
  for (final m in _word.allMatches(fold(s))) m[0]!,
];

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

/// A whole word beats a prefix, so a stop's code "61" comes before 610-619.
int _wordScore(String q, List<String> name) {
  var best = 0;
  for (final w in name) {
    if (w == q) return 4;
    if (w.startsWith(q)) {
      best = 3;
    } else if (q.length >= 3 && w.contains(q)) {
      best = max(best, 2);
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
