import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:latlong2/latlong.dart';

import 'package:commuterlviv/src/match.dart';
import 'package:commuterlviv/src/models.dart';

/// What NFKD folds each Latin and Cyrillic letter to, which the web's folding
/// is checked against too (`tests/fold_test.py`).
final _folds = [
  for (final c
      in (jsonDecode(
            File('../tests/fold_cases.json').readAsStringSync(),
          )['cases']
          as List))
    (c as List).cast<String>(),
];

int of(String q, String name) => score(words(q), words(name));

List<String> names(String q, List<String> saved) => [
  for (final p in matching([
    for (final n in saved) Place(name: n, at: const LatLng(49.84, 24.03)),
  ], q))
    p.name,
];

void main() {
  test('words match in any order, by prefix', () {
    expect(of('шевч пл', 'Площа Шевченка'), greaterThan(0));
    expect(of('ринок', 'Площа Ринок'), greaterThan(0));
  });

  test('й and ї fold, apostrophes are not typed', () {
    expect(of('иорд', 'Йорданська'), of('йорд', 'Йорданська'));
    expect(of('обєднання', 'Обʼєднання'), greaterThan(0));
  });

  test('one slip is forgiven in a longer word, none in a short one', () {
    expect(of('стрийска', 'Стрийська'), greaterThan(0));
    expect(of('рнк', 'Ринок'), 0);
    expect(of('xyz', 'Площа Ринок'), 0);
  });

  test('a prefix outranks a slip', () {
    expect(
      of('стрийсь', 'Стрийська'),
      greaterThan(of('стрийска', 'Стрийська')),
    );
  });

  test('saved places match the way stops are matched', () {
    expect(names('роб', ['Дім', 'Робота']), ['Робота']);
    expect(names('мами д', ['Дім мами', 'Дім']), ['Дім мами']);
  });

  test('saved places: closer matches first, shorter names among equals', () {
    expect(names('спорт', ['Спортзал біля роботи', 'Спортзал', 'Спорт']), [
      'Спорт',
      'Спортзал',
      'Спортзал біля роботи',
    ]);
    expect(names('hone', ['Phone shop', 'Home']), ['Phone shop', 'Home']);
  });

  test('saved places wait for a second letter', () {
    expect(names('д', ['Дім']), isEmpty);
  });

  test('every letter folds as the web folds it', () {
    expect([
      for (final [c, _] in _folds) [c, fold(c)],
    ], _folds);
  });
}
