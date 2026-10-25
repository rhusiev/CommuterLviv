/// Android's back button, from a widget test.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Presses back as the system sends it, and says whether the app left: with
/// nothing to pop, Flutter hands back to the system with `SystemNavigator.pop`.
Future<bool> pressBack(WidgetTester tester) async {
  var left = false;
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'SystemNavigator.pop') left = true;
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  await tester.binding.handlePopRoute();
  await tester.pump();
  return left;
}
