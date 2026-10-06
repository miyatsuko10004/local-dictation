import XCTest
@testable import DictationCore
final class HeadsetTests: XCTestCase {
 func testDedupeAndDebounce() {
  var gate = HeadsetEventGate()
  let first = UUID().uuidString, second = UUID().uuidString
  XCTAssertTrue(gate.accept(first, now: 10))
  XCTAssertFalse(gate.accept(first, now: 12))
  XCTAssertFalse(gate.accept(second, now: 10.5))
  XCTAssertTrue(gate.accept(UUID().uuidString, now: 11))
  XCTAssertFalse(gate.accept("invalid", now: 20))
 }
 func testPreferencesMigrationAndRoundTrip() throws {
  let old = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
  XCTAssertNil(old.microphoneUID); XCTAssertFalse(old.headsetEnabled)
  var value = old; value.microphoneUID = "BT-input-UID"; value.headsetEnabled = true
  XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(value)), value)
 }
}
extension HeadsetTests {
 func testAudioRecoveryIsBoundedAndPinsDevice() {
  var budget = AudioRecoveryBudget()
  XCTAssertFalse(budget.allow(selectedUID: "headset", connectedUID: nil, now: 0))
  XCTAssertFalse(budget.allow(selectedUID: "headset", connectedUID: "other", now: 0))
  XCTAssertTrue(budget.allow(selectedUID: "headset", connectedUID: "headset", now: 1))
  XCTAssertTrue(budget.allow(selectedUID: "headset", connectedUID: "headset", now: 2))
  XCTAssertFalse(budget.allow(selectedUID: "headset", connectedUID: "headset", now: 3))
  var expired = AudioRecoveryBudget()
  XCTAssertTrue(expired.allow(selectedUID: "headset", connectedUID: "headset", now: 10))
  XCTAssertFalse(expired.allow(selectedUID: "headset", connectedUID: "headset", now: 21))
 }
}
