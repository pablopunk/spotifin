import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testPendingDeepLinkIsConsumedExactlyOnce() {
    _ = DeepLinkStore.takePendingLink()
    defer { _ = DeepLinkStore.takePendingLink() }
    let link = "spotifin://play-library"
    DeepLinkStore.store(link)

    XCTAssertEqual(DeepLinkStore.takePendingLink(), link)
    XCTAssertNil(DeepLinkStore.takePendingLink())
  }

}
