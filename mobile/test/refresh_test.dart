import 'package:flutter_test/flutter_test.dart';

import 'package:commuterlviv/src/refresh.dart';

void main() {
  test('the followed way is searched again every 30 s', () {
    expect(refreshEveryS, 30);
  });
}
