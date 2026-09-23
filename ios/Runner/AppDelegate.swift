import Flutter
import AVKit
import CarPlay
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
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "SpotifinDeepLink"
    ) {
      let channel = FlutterMethodChannel(
        name: "spotifin/deep-link",
        binaryMessenger: registrar.messenger()
      )
      DeepLinkStore.attach(channel: channel)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "SpotifinCarPlayShuffle"
    ) {
      let channel = FlutterMethodChannel(
        name: "spotifin/carplay_shuffle",
        binaryMessenger: registrar.messenger()
      )
      CarPlayShuffle.attach(channel: channel)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "SpotifinCarPlayUpNext"
    ) {
      let channel = FlutterMethodChannel(
        name: "spotifin/carplay_up_next",
        binaryMessenger: registrar.messenger()
      )
      CarPlayUpNext.attach(channel: channel)
    }
  }
}

private enum CarPlayShuffle {
  static func attach(channel: FlutterMethodChannel) {
    let button = CPNowPlayingShuffleButton { _ in
      channel.invokeMethod("toggleShuffle", arguments: nil)
    }
    CPNowPlayingTemplate.shared.updateNowPlayingButtons([button])
    channel.setMethodCallHandler { call, result in
      guard call.method == "setShuffle", let enabled = call.arguments as? Bool else {
        result(FlutterMethodNotImplemented)
        return
      }
      button.isSelected = enabled
      result(nil)
    }
  }
}

private final class CarPlayUpNext: NSObject, CPNowPlayingTemplateObserver {
  private let channel: FlutterMethodChannel
  private static var observer: CarPlayUpNext?

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  static func attach(channel: FlutterMethodChannel) {
    if let observer { CPNowPlayingTemplate.shared.remove(observer) }
    let observer = CarPlayUpNext(channel: channel)
    self.observer = observer
    CPNowPlayingTemplate.shared.upNextTitle = "Up Next"
    CPNowPlayingTemplate.shared.add(observer)
    channel.setMethodCallHandler { call, result in
      guard call.method == "setUpNextEnabled", let enabled = call.arguments as? Bool else {
        result(FlutterMethodNotImplemented)
        return
      }
      CPNowPlayingTemplate.shared.isUpNextButtonEnabled = enabled
      result(nil)
    }
  }

  func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
    channel.invokeMethod("showUpNext", arguments: nil)
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
