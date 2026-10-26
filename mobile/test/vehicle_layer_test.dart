import 'package:flutter_test/flutter_test.dart';

import 'package:commuterlviv/src/vehicle_layer.dart';

void main() {
  test(
    'every stop can be tapped from close in, a watched one from further out',
    () {
      const watched = [3];
      const faint = [7];

      expect(pickableStops(stopsZoom - 0.1, watched, faint), isEmpty);
      expect(pickableStops(stopsZoom, watched, faint), watched);
      expect(pickableStops(allStopsZoom - 0.1, watched, faint), watched);
      expect(pickableStops(allStopsZoom, watched, faint), [3, 7]);
    },
  );
}
