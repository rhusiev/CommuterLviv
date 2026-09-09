/// Where the phone thinks it is.
///
/// The states are the browser's, from `web/src/components/MapCanvas.tsx`:
/// nothing is asked of the operating system until the button is pressed, so
/// the app can be used - and installed - by somebody who never grants location
/// at all. The fix is kept here and nowhere else; it is never sent to the
/// service, which has no use for it.
///
/// The platform half is hand-written - `MainActivity.kt` over AOSP's
/// `LocationManager` - rather than `geolocator`, which pulls Google Play
/// services and would keep the build out of F-Droid. Only Android has a half:
/// on anything else the channel is missing, which reads here as a refusal.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

const _channel = MethodChannel('ua.lviv.commuterlviv/here');
const _fixes = EventChannel('ua.lviv.commuterlviv/here/fixes');

enum Locating {
  /// Never asked for
  off,

  /// Asked for, no fix yet
  waiting,

  /// A fix is in hand
  on,

  /// Refused, or the phone's location is switched off
  denied,
}

class Fix {
  const Fix(this.point, this.accuracy);

  final LatLng point;

  /// Metres, as the phone reports it - drawn, because a 300 m fix shown as a
  /// dot claims a precision it never had
  final double accuracy;
}

class Here extends ChangeNotifier {
  Here({required this.onFirstFix});

  /// Only the first fix moves the camera; after that the dot moves and the
  /// view stays where the user put it
  final void Function(LatLng at) onFirstFix;

  Locating state = Locating.off;
  Fix? fix;

  StreamSubscription<dynamic>? _stream;
  bool _first = true;

  /// Asks, then follows. Called again once following, it only says where the
  /// phone is - the caller decides what to do with that.
  Future<LatLng?> start() async {
    if (state == Locating.on) return fix?.point;
    if (_stream != null) return null;

    state = Locating.waiting;
    notifyListeners();

    // The stream is subscribed before the permission is asked for: the
    // platform side answers `start` only once it has somewhere to send fixes
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
