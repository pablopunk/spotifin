import Flutter
import GoogleCast

final class CastVolumeBridge: NSObject, FlutterStreamHandler, GCKSessionManagerListener {
  private static var instance: CastVolumeBridge?
  private var events: FlutterEventSink?

  static func attach(messenger: FlutterBinaryMessenger) {
    let bridge = CastVolumeBridge()
    instance = bridge
    FlutterEventChannel(name: "spotifin/cast_volume", binaryMessenger: messenger)
      .setStreamHandler(bridge)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.events = events
    let manager = GCKCastContext.sharedInstance().sessionManager
    manager.add(self)
    if let session = manager.currentSession {
      events(Double(session.currentDeviceVolume))
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    GCKCastContext.sharedInstance().sessionManager.remove(self)
    events = nil
    return nil
  }

  func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
    events?(Double(session.currentDeviceVolume))
  }

  func sessionManager(_ sessionManager: GCKSessionManager, didResume session: GCKSession) {
    events?(Double(session.currentDeviceVolume))
  }

  func sessionManager(_ sessionManager: GCKSessionManager, session: GCKSession, didReceiveDeviceVolume volume: Float, muted: Bool) {
    events?(Double(volume))
  }

  func sessionManager(_ sessionManager: GCKSessionManager, castSession session: GCKCastSession, didReceiveDeviceVolume volume: Float, muted: Bool) {
    events?(Double(volume))
  }
}
