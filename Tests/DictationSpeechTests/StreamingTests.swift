import XCTest
import AVFoundation
import WhisperKit
@testable import DictationSpeech
final class StreamingTests: XCTestCase {
    func testContinuousChunkingKeepsAllNewSamplesAndOverlap() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let writer = try AudioChunkWriter(directory: base, minimumSeconds: 0.1, maximumSeconds: 0.2, overlapSeconds: 0.05)
        for _ in 0..<5 { writer.append(Array(repeating: Float(0.2), count: 1600)) }
        let files = try writer.finish()
        XCTAssertEqual(writer.totalSamples, 8000)
        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(files.map(\.newSampleCount).reduce(0,+), 8000)
        XCTAssertTrue(files.allSatisfy(\.voiced))
        XCTAssertEqual(try AVAudioFile(forReading: files[1].url).length, 4000)
        writer.append([0.2])
        XCTAssertEqual(writer.totalSamples, 8000)
    }
    func testEngineAcceptedSpeechAndBoundarySpacesArePreserved() {
        let segments = [TranscriptionSegment(text: "API is", noSpeechProb: 0.99), TranscriptionSegment(text: " ready", noSpeechProb: 0.2)]
        XCTAssertEqual(SpeechService.joinAcceptedSegments(segments), "API is ready")
    }
    func testSilenceDoesNotCountAsSpeech() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let writer = try AudioChunkWriter(directory: base)
        writer.append(Array(repeating: 0, count: 16000))
        XCTAssertFalse(try writer.finish()[0].voiced)
    }
    func testConcatenationNeverDeletesRepeatedSpeech() {
        XCTAssertEqual(TranscriptMerger.join("API is", " ready"), "API is ready")
        XCTAssertEqual(TranscriptMerger.join("数値", "123です"), "数値123です")
        XCTAssertEqual(TranscriptMerger.join("来週の予定です。", "予定です。水曜日です。"), "来週の予定です。予定です。水曜日です。")
        XCTAssertEqual(TranscriptMerger.join("これは重要です。", "変更しません。"), "これは重要です。変更しません。")
        XCTAssertEqual(TranscriptMerger.join("", "最初です。"), "最初です。")
        XCTAssertEqual(TranscriptMerger.join("確認してください。", "確認してください。再度確認してください。"), "確認してください。確認してください。再度確認してください。")
    }
}
