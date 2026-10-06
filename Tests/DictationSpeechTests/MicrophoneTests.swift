import XCTest
@testable import DictationSpeech
final class MicrophoneTests: XCTestCase {
 func testExplicitSelectionNeverFallsBack() throws {
  let inputs = [MicrophoneDevice(id: 1, uid: "a", name: "USB"), MicrophoneDevice(id: 2, uid: "b", name: "Headset")]
  XCTAssertEqual(try MicrophoneDevices.resolve(uid: "b", devices: inputs, defaultID: 1).id, 2)
  XCTAssertEqual(try MicrophoneDevices.resolve(uid: nil, devices: inputs, defaultID: 1).id, 1)
  XCTAssertThrowsError(try MicrophoneDevices.resolve(uid: "gone", devices: inputs, defaultID: 1))
  XCTAssertThrowsError(try MicrophoneDevices.resolve(uid: nil, devices: inputs, defaultID: 99))
 }
}
