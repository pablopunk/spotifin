import Flutter
import UIKit

final class DeepLinkStore {
  static var pendingLink: String?
  private static var channel: FlutterMethodChannel?

  static func attach(channel: FlutterMethodChannel) {
    self.channel = channel
    channel.setMethodCallHandler { call, result in
      if call.method == "getInitialLink" {
        let link = pendingLink
        pendingLink = nil
        result(link)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func store(_ link: String) {
    pendingLink = link
  }

  static func push(_ link: String) {
    pendingLink = link
    guard let channel else { return }
    channel.invokeMethod("onLink", arguments: link) { response in
      if !(response is FlutterError) && pendingLink == link {
        pendingLink = nil
      }
    }
  }
}

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let url = connectionOptions.urlContexts.first?.url,
      url.scheme == "spotifin"
    {
      DeepLinkStore.store(url.absoluteString)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    if let url = URLContexts.first?.url, url.scheme == "spotifin" {
      DeepLinkStore.push(url.absoluteString)
    }
  }
}
