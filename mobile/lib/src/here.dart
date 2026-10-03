/// Where the phone thinks it is. Nothing is asked of the OS until the button
/// is pressed, and the fix never leaves the device.
///
/// The platform half is hand-written (`MainActivity.kt`, `ios/Runner/Here.swift`)
/// rather than `geolocator`, which would pull Play services and bar F-Droid.
/// Both answer the same two channels; elsewhere the channel is missing, which
/// reads as a refusal.
///
/// Fixes stop when the app leaves the screen, unless [away] asked for them to
/// go on: then Android runs a foreground service with a notification, and iOS
/// keeps its updates with the location indicator up.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

const _channel = MethodChannel('nl.r1a.commuterlviv/here');
const _fixes = EventChannel('nl.r1a.commuterlviv/here/fixes');

enum Locating {
  off,

  waiting,

  on,

  /// Refused, or location is switched off.
  denied,
}

class Fix {
  const Fix(this.point, this.accuracy, this.t);

  final LatLng point;

  /// Metres, as the phone reports it.
  final double accuracy;

  /// When the phone took it, in milliseconds since the epoch. Not when it
  /// arrived: the first may be the last one known, from long before.
  final int t;
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

    if (!await _call('start')) return _deny();
    return null;
  }

  /// Whether fixes go on with the app off the screen. [channel] and [alerts]
  /// name the notification channels where the phone lists them. False when
  /// that is refused, or the platform has no way to.
  Future<bool> away(
    bool on, {
    required String channel,
    required String alerts,
  }) => _call('away', {'on': on, 'channel': channel, 'alerts': alerts});

  /// Says [title] and [text] on the notification [away] keeps up, and with
  /// [alert] makes the phone sound for it.
  Future<bool> notice(String title, String text, {bool alert = false}) =>
      _call('notice', {'title': title, 'text': text, 'alert': alert});

  Future<bool> _call(String method, [Map<String, Object>? args]) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  void _arrived(dynamic event) {
    final f = (event as Map).cast<String, double>();
    final at = LatLng(f['lat']!, f['lon']!);
    fix = Fix(at, f['accuracy']!, f['t']!.toInt());
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
