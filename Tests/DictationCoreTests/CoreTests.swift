import XCTest
@testable import DictationCore
final class CoreTests: XCTestCase {
    func testWorkflowRejectsOverlapAndCancelInvalidatesResult() {
        var flow = Workflow()
        let first = flow.begin()!
        XCTAssertNil(flow.begin())
        XCTAssertTrue(flow.stop(first))
        flow.cancel()
        XCTAssertFalse(flow.accepts(first))
        XCTAssertNotNil(flow.begin())
    }
    func testOnlyProcessingGenerationCanFinish() {
        var flow = Workflow()
        let token = flow.begin()!
        XCTAssertFalse(flow.finish(token))
        XCTAssertTrue(flow.stop(token))
        XCTAssertTrue(flow.finish(token))
        XCTAssertFalse(flow.finish(token))
    }
    func testCleanupProtectsNumbersURLsAndIdentifiers() {
        XCTAssertEqual(CleanupPolicy.choose(original: "期限は10月6日です", candidate: "期限は10月7日です"), "期限は10月6日です")
        XCTAssertEqual(CleanupPolicy.choose(original: "foo_barをhttps://example.comへ送る", candidate: "foobarをhttps://example.comへ送る"), "foo_barをhttps://example.comへ送る")
        XCTAssertEqual(CleanupPolicy.choose(original: "えー、明日です", candidate: "明日です。"), "明日です。")
        XCTAssertEqual(CleanupPolicy.choose(original: "送信しないでください", candidate: "送信してください"), "送信しないでください")
        XCTAssertEqual(CleanupPolicy.choose(original: "日本語", candidate: ""), "日本語")
    }
    func testModelNamesCannotSelectCloud() {
        XCTAssertTrue(CleanupPolicy.isLocalModel("qwen3:4b"))
        XCTAssertFalse(CleanupPolicy.isLocalModel("gpt-oss:120b-cloud"))
        XCTAssertFalse(CleanupPolicy.isLocalModel("https://example.com"))
    }
}

final class OllamaInputPolicyTests: XCTestCase {
 func testMultibyteInputBudget() {
  XCTAssertTrue(OllamaInputPolicy.accepts(String(repeating: "あ", count: 533)))
  XCTAssertFalse(OllamaInputPolicy.accepts(String(repeating: "あ", count: 534)))
  XCTAssertTrue(OllamaInputPolicy.accepts(String(repeating: "a", count: 1600)))
  XCTAssertFalse(OllamaInputPolicy.accepts(String(repeating: "a", count: 1601)))
 }
}
