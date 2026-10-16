/// Haptics for actions that move the camera.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

bool get _cupertino => !kIsWeb && Platform.isIOS;

/// The platform's own light tap.
void tick() {
  if (_cupertino) {
    HapticFeedback.selectionClick();
  } else {
    HapticFeedback.lightImpact();
  }
}
