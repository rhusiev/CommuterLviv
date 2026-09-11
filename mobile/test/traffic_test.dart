import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:commuterlviv/src/traffic.dart';

void main() {
  test('a stretch with too little seen on it is drawn as nothing', () {
    expect(trafficColour(null), isNull);
  });

  test('the ramp runs from free-flowing to a crawl', () {
    expect(trafficColour(0.2), trafficRamp.first.$2);
    expect(trafficColour(0.85), trafficRamp.first.$2);
    expect(trafficColour(1.6), trafficRamp.last.$2);
    expect(trafficColour(3), trafficRamp.last.$2);
  });

  test('between two stops the colour is mixed', () {
    final middle = trafficColour(0.925)!;
    final half = Color.lerp(
      trafficRamp[0].$2,
      trafficRamp[1].$2,
      (0.925 - trafficRamp[0].$1) / (trafficRamp[1].$1 - trafficRamp[0].$1),
    )!;
    expect(middle.toARGB32(), half.toARGB32());
    expect(middle.toARGB32(), isNot(trafficRamp[0].$2.toARGB32()));
  });
}
