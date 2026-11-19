import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:commuterlviv/src/refresh.dart';

void main() {
  test('the followed way is searched again every 30 s', () {
    expect(refreshEveryS, 30);
  });

  test('ticks every 30 s, and not while the setting is off', () {
    fakeAsync((async) {
      var on = false;
      var asked = 0;
      final r = RouteRefresh(enabled: () => on, ask: () => asked++);
      r.start();
      addTearDown(r.stop);

      async.elapse(const Duration(seconds: 29));
      expect(asked, 0);

      on = true;
      async.elapse(const Duration(seconds: 1));
      expect(asked, 1);

      on = false;
      async.elapse(const Duration(seconds: 30));
      expect(asked, 1);

      r.stop();
    });
  });
}
