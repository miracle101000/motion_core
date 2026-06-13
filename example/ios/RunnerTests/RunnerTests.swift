import Flutter
import UIKit
import XCTest


@testable import motion_core

// This demonstrates a simple unit test of the Swift portion of this plugin's implementation.
//
// See https://developer.apple.com/documentation/xctest for more information about using XCTest.

class RunnerTests: XCTestCase {

  func testIsAvailableReturnsBoolean() {
    let plugin = MotionCorePlugin()

    let call = FlutterMethodCall(methodName: "isAvailable", arguments: nil)

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      XCTAssertTrue(result is Bool)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

}
