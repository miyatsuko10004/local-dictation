import XCTest
@testable import DictationCore
final class MemoryPolicyTests: XCTestCase {
 func testPressureSkipsOptionalLLM() {
  XCTAssertTrue(MemoryPolicy.shouldSkipOptionalLLM(pressure: .warning, availableBytes: nil))
  XCTAssertTrue(MemoryPolicy.shouldSkipOptionalLLM(pressure: .critical, availableBytes: 8 * 1024 * 1024 * 1024))
  XCTAssertFalse(MemoryPolicy.shouldSkipOptionalLLM(pressure: .normal, availableBytes: nil))
 }
 func testAvailableMemoryThreshold() {
  let threshold: UInt64 = 2 * 1024 * 1024 * 1024
  XCTAssertTrue(MemoryPolicy.shouldSkipOptionalLLM(pressure: .normal, availableBytes: 0))
  XCTAssertTrue(MemoryPolicy.shouldSkipOptionalLLM(pressure: .normal, availableBytes: threshold - 1))
  XCTAssertFalse(MemoryPolicy.shouldSkipOptionalLLM(pressure: .normal, availableBytes: threshold))
  XCTAssertFalse(MemoryPolicy.shouldSkipOptionalLLM(pressure: .normal, availableBytes: UInt64.max))
 }
 func testOlderPreferencesPreserveSettingsWithoutPushToTalk() throws {
  let json = #"{"cleanupEnabled":true,"autoPaste":false,"hotKeyCode":40,"hotKeyModifiers":4096,"maxRecordingSeconds":300,"idleUnloadSeconds":90,"cleanupModel":"qwen3:4b"}"#
  let preferences = try JSONDecoder().decode(Preferences.self, from: Data(json.utf8))
  XCTAssertFalse(preferences.pushToTalk)
  XCTAssertTrue(preferences.cleanupEnabled)
  XCTAssertFalse(preferences.autoPaste)
  XCTAssertEqual(preferences.hotKeyCode, 40)
  XCTAssertEqual(preferences.hotKeyModifiers, 4096)
  XCTAssertEqual(preferences.maxRecordingSeconds, 300)
  XCTAssertEqual(preferences.idleUnloadSeconds, 90)
 }
 func testPushToTalkRoundTrip() throws {
  var preferences = Preferences(); preferences.pushToTalk = true
  XCTAssertEqual(try JSONDecoder().decode(Preferences.self,from:JSONEncoder().encode(preferences)),preferences)
 }
}
