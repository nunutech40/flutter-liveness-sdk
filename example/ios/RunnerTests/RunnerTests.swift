import Flutter
import XCTest
@testable import flutter_liveness_sdk

final class RunnerTests: XCTestCase {
  func testRejectsInvalidConfiguration() {
    let plugin = FlutterLivenessSdkPlugin()
    let call = FlutterMethodCall(methodName: "capture", arguments: ["steps": []])
    let completed = expectation(description: "invalid config returns")
    plugin.handle(call) { value in
      let error = value as? FlutterError
      XCTAssertEqual(error?.code, "invalid_config")
      completed.fulfill()
    }
    wait(for: [completed], timeout: 1)
  }
}
