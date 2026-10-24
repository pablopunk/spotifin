import XCTest
import CarPlay
import Flutter
import MediaPlayer
@testable import Runner

class RunnerTests: XCTestCase {

  func testCarPlayShuffleHighlightFollowsPlaybackState() throws {
    let messenger = ShuffleTestMessenger()
    let channel = FlutterMethodChannel(
      name: "spotifin/test_carplay_shuffle",
      binaryMessenger: messenger
    )
    CarPlayShuffle.attach(channel: channel)
    let button = try XCTUnwrap(CPNowPlayingTemplate.shared.nowPlayingButtons.first)
    // A system shuffle button ignores manual selection; the image button must
    // remain selected even if MediaPlayer's independently managed mode changes.
    XCTAssertTrue(button is CPNowPlayingImageButton)
    let handler = try XCTUnwrap(messenger.handler)
    let codec = FlutterStandardMethodCodec.sharedInstance()
    for enabled in [false, true, false, true] {
      var acknowledged = false
      handler(codec.encode(FlutterMethodCall(methodName: "setShuffle", arguments: enabled))) { _ in
        acknowledged = true
      }
      XCTAssertTrue(acknowledged)
      XCTAssertEqual(button.isSelected, enabled)
      XCTAssertEqual(
        MPRemoteCommandCenter.shared().changeShuffleModeCommand.currentShuffleType,
        enabled ? .items : .off
      )
      MPRemoteCommandCenter.shared().changeShuffleModeCommand.currentShuffleType = .off
      XCTAssertEqual(button.isSelected, enabled)
      XCTAssertTrue(CPNowPlayingTemplate.shared.nowPlayingButtons.first === button)
    }
  }

  func testPendingDeepLinkIsConsumedExactlyOnce() {
    _ = DeepLinkStore.takePendingLink()
    defer { _ = DeepLinkStore.takePendingLink() }
    let link = "spotifin://play-library"
    DeepLinkStore.store(link)

    XCTAssertEqual(DeepLinkStore.takePendingLink(), link)
    XCTAssertNil(DeepLinkStore.takePendingLink())
  }

}

private final class ShuffleTestMessenger: NSObject, FlutterBinaryMessenger {
  var handler: FlutterBinaryMessageHandler?

  func send(onChannel channel: String, message: Data?) {}

  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {
    callback?(nil)
  }

  func setMessageHandlerOnChannel(
    _ channel: String,
    binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection {
    self.handler = handler
    return 1
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {
    handler = nil
  }
}
