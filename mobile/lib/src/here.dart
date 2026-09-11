/// Where the phone thinks it is. Nothing is asked of the OS until the button
/// is pressed, and the fix never leaves the device.
///
/// The platform half is hand-written (`MainActivity.kt`, `ios/Runner/Here.swift`)
/// rather than `geolocator`, which would pull Play services and bar F-Droid.
/// Both answer the same two channels; elsewhere the channel is missing, which
/// reads as a refusal.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

const _channel = MethodChannel('ua.lviv.commuterlviv/here');
const _fixes = EventChannel('ua.lviv.commuterlviv/here/fixes');

enum Locating {
  off,

  waiting,

  on,

  /// Refused, or location is switched off.
  denied,
}

class Fix {
  const Fix(this.point, this.accuracy);

  final LatLng point;

  /// Metres, as the phone reports it.
  final double accuracy;
}

class Here extends ChangeNotifier {
  Here({required this.onFirstFix});

  /// Only the first fix moves the camera.
  final void Function(LatLng at) onFirstFix;

  Locating state = Locating.off;
  Fix? fix;

  StreamSubscription<dynamic>? _stream;
  bool _first = true;

  Future<LatLng?> start() async {
    if (state == Locating.on) return fix?.point;
    if (_stream != null) return null;

    state = Locating.waiting;
    notifyListeners();

    // Subscribe before asking: the platform side answers `start` only once it
    // has somewhere to send fixes
    _stream = _fixes.receiveBroadcastStream().listen(
      _arrived,
      onError: (_) {
        _deny();
      },
    );

    bool granted;
    try {
      granted = await _channel.invokeMethod<bool>('start') ?? false;
    } on PlatformException {
      granted = false;
    } on MissingPluginException {
      granted = false;
    }
    if (!granted) return _deny();
    return null;
  }

  void _arrived(dynamic event) {
    final f = (event as Map).cast<String, double>();
    final at = LatLng(f['lat']!, f['lon']!);
    fix = Fix(at, f['accuracy']!);
    state = Locating.on;
    if (_first) {
      _first = false;
      onFirstFix(at);
    }
    notifyListeners();
  }

  Null _deny() {
    _stop();
    fix = null;
    state = Locating.denied;
    notifyListeners();
    return null;
  }

  void _stop() {
    _stream?.cancel();
    _stream = null;
    _channel.invokeMethod<void>('stop').catchError((_) {});
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }
}
