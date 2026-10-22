import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:commuterlviv/src/models.dart';
import 'package:commuterlviv/src/route_badge.dart';
import 'package:commuterlviv/src/route_chip.dart';
import 'package:commuterlviv/src/strings.dart';

const _route = TransitRoute(
  id: 'r48',
  short: '48',
  long: 'A to B',
  type: 'bus',
);

Future<({List<String> taps})> _pump(
  WidgetTester tester, {
  bool watched = false,
  double? width,
}) async {
  final taps = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: RouteChip(
            route: _route,
            watched: watched,
            width: width,
            onWatch: () => taps.add('watch'),
            onLine: () => taps.add('line'),
          ),
        ),
      ),
    ),
  );
  return (taps: taps);
}

void main() {
  testWidgets('the body watches the route and the chevron opens its line', (
    tester,
  ) async {
    final (:taps) = await _pump(tester);

    await tester.tap(find.byType(RouteBadge));
    expect(taps, ['watch']);
    await tester.tap(find.byIcon(Icons.chevron_right));
    expect(taps, ['watch', 'line']);
  });

  testWidgets('a long press is a tap, not a way to the line', (tester) async {
    final (:taps) = await _pump(tester);

    await tester.longPress(find.byType(RouteBadge));
    expect(taps, ['watch']);
  });

  testWidgets('says whether the route is watched and names the line part', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, watched: true);

    expect(
      tester.getSemantics(find.byType(RouteBadge)),
      containsSemantics(
        isButton: true,
        isToggled: true,
        hasTapAction: true,
        hint: txt.unwatchRoute,
        label: '48',
      ),
    );
    expect(find.bySemanticsLabel(txt.lineOf('48')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('takes the width given and the height of a tap target', (
    tester,
  ) async {
    await _pump(tester, width: 120);

    expect(tester.getSize(find.byType(RouteChip)).width, 120);
    expect(
      tester.getSize(find.byType(RouteChip)).height,
      kMinInteractiveDimension,
    );
  });
}
