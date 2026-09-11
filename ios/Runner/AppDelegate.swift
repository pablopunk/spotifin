import Flutter
import AVKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    engineBridge.pluginRegistry.registrar(forPlugin: "SpotifinAirPlay")?.register(
      AirPlayViewFactory(),
      withId: "spotifin_airplay"
    )
  }
}

private final class AirPlayViewFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> any FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> any FlutterPlatformView {
    AirPlayPlatformView(frame: frame)
  }
}

private final class AirPlayPlatformView: NSObject, FlutterPlatformView {
  private let routePicker: AVRoutePickerView

  init(frame: CGRect) {
    routePicker = AVRoutePickerView(frame: frame)
    routePicker.prioritizesVideoDevices = false
    routePicker.tintColor = .white
    routePicker.activeTintColor = UIColor(
      red: 57 / 255,
      green: 244 / 255,
      blue: 209 / 255,
      alpha: 1
    )
    super.init()
  }

  func view() -> UIView {
    routePicker
  }
}
