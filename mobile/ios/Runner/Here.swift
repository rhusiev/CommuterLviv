import CoreLocation
import Flutter

/// Where the phone is, over CoreLocation - the other half of
/// `android/app/src/main/kotlin/nl/r1a/commuterlviv/MainActivity.kt`.
///
/// The two channels and their shapes are the Android ones exactly, because
/// `lib/src/here.dart` talks to both through one code path: `start` answers
/// true once something is feeding fixes, and each fix is one
/// `{lat, lon, accuracy}` map. Nothing is asked of the system until `start`,
/// and the updates stop when the app leaves the screen.
///
/// CoreLocation is part of iOS, so nothing here costs the build its place in
/// F-Droid the way `geolocator` would.
private let channelName = "nl.r1a.commuterlviv/here"
private let fixesName = "nl.r1a.commuterlviv/here/fixes"

final class Here: NSObject, CLLocationManagerDelegate, FlutterStreamHandler {
  private let locations = CLLocationManager()
  private var fixes: FlutterEventSink?

  /// The `start` that is waiting on the system's permission dialog
  private var asking: FlutterResult?

  private var listening = false

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    locations.delegate = self
    locations.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    // Metres: the Android half filters at five, and a dot that redraws for
    // less than that is only spending battery
    locations.distanceFilter = 5

    FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard let self else { return }
        switch call.method {
        case "start": self.start(result)
        case "stop":
          self.unlisten()
          result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      }

    FlutterEventChannel(name: fixesName, binaryMessenger: messenger)
      .setStreamHandler(self)
  }

  private func start(_ result: @escaping FlutterResult) {
    switch locations.authorizationStatus {
    case .authorizedWhenInUse, .authorizedAlways:
      result(listen())
    case .notDetermined:
      // One request at a time: a second tap while the dialog is up must not
      // leave the first call unanswered
      asking?(false)
      asking = result
      locations.requestWhenInUseAuthorization()
    default:
      result(false)
    }
  }

  /// True if anything is now feeding the stream
  private func listen() -> Bool {
    guard !listening else { return true }
    guard CLLocationManager.locationServicesEnabled() else { return false }
    locations.startUpdatingLocation()
    listening = true
    return true
  }

  private func unlisten() {
    guard listening else { return }
    locations.stopUpdatingLocation()
    listening = false
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard let waiting = asking else { return }
    switch manager.authorizationStatus {
    case .notDetermined: return  // the dialog is still up
    case .authorizedWhenInUse, .authorizedAlways:
      asking = nil
      waiting(listen())
    default:
      asking = nil
      waiting(false)
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations fixes: [CLLocation]) {
    guard let fix = fixes.last, let sink = self.fixes else { return }
    sink([
      "lat": fix.coordinate.latitude,
      "lon": fix.coordinate.longitude,
      // Negative means the phone does not know; the Dart side draws a ring
      // from this, and a ring of minus ten metres is worse than none
      "accuracy": max(fix.horizontalAccuracy, 0),
    ])
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    // A single failed fix is not a refusal - CoreLocation keeps trying, and
    // the dot simply stays where it was
  }

  func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink)
    -> FlutterError?
  {
    fixes = eventSink
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    fixes = nil
    unlisten()
    return nil
  }

  /// Nothing on this map is worth a fix taken while it is not on screen
  func background() {
    unlisten()
  }

  func foreground() {
    if fixes != nil { _ = listen() }
  }
}
