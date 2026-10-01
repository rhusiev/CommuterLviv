import 'package:flutter_test/flutter_test.dart';

import 'package:commuterlviv/src/match.dart';

int of(String q, String name) => score(words(q), words(name));

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
}
