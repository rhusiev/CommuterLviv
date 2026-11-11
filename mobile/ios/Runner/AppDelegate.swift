import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var here: Here?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Registering as a plugin is only how one gets a messenger here; `Here` is
    // part of this app and not a package
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Here") {
      here = Here(messenger: registrar.messenger())
    }
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    here?.background()
    super.applicationDidEnterBackground(application)
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    here?.foreground()
    super.applicationWillEnterForeground(application)
  }
}
