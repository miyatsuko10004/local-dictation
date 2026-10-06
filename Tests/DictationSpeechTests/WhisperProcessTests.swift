import XCTest
import Darwin
@testable import DictationSpeech
final class WhisperProcessTests: XCTestCase {
 private func fixture(_ body: String) throws -> (URL,URL,URL,URL) {
  let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
  let executable = base.appendingPathComponent("stub"), model = base.appendingPathComponent("model.bin"), audio = base.appendingPathComponent("audio.wav")
  try Data(("#!/bin/sh\n" + body).utf8).write(to:executable)
  try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:executable.path)
  try Data([0]).write(to:model); try Data([0]).write(to:audio)
  return (base,executable,model,audio)
 }
 func testJapaneseOutputAndArguments() async throws {
  let (base,exe,model,audio) = try fixture("test \"$1\" = '-m' || exit 3\ntest \"$5\" = '-l' || exit 4\ntest \"$6\" = 'ja' || exit 5\ntest \"$9\" = '-nt' || exit 6\nprintf 'こんにちは、日本語です。\\n'\n")
  defer { try? FileManager.default.removeItem(at:base) }
  let client = WhisperProcess(executable:exe,model:model)
  let prepared = await client.isPrepared; XCTAssertTrue(prepared)
  let text = try await client.transcribe(file:audio,prompt:"日本語")
  XCTAssertEqual(text,"こんにちは、日本語です。\n")
 }
 func testNonzeroExitThrows() async throws {
  let (base,exe,model,audio) = try fixture("echo bad >&2\nexit 7\n")
  defer { try? FileManager.default.removeItem(at:base) }
  do { _ = try await WhisperProcess(executable:exe,model:model).transcribe(file:audio); XCTFail("must throw") } catch {}
 }
 func testTimeoutReapsChild() async throws {
  let (base,exe,model,audio) = try fixture("echo $$ > \"${2}.pid\"\nwhile :; do :; done\n")
  defer { try? FileManager.default.removeItem(at:base) }
  let observed = ObservedPID()
  let client = WhisperProcess(executable:exe,model:model,timeout:0.15)
  await client.observeProcessStart { observed.set($0) }
  let start = Date()
  do { _ = try await client.transcribe(file:audio); XCTFail("must timeout") } catch { XCTAssertTrue(error.localizedDescription.contains("timed out")) }
  XCTAssertLessThan(Date().timeIntervalSince(start),3)
  let pid = try XCTUnwrap(observed.value)
  XCTAssertEqual(Darwin.kill(pid,0),-1)
  XCTAssertEqual(errno,ESRCH)
 }
 func testCancellationAndOverlap() async throws {
  let (base,exe,model,audio) = try fixture("echo $$ > \"${2}.pid\"\nwhile :; do :; done\n")
  defer { try? FileManager.default.removeItem(at:base) }
  let client = WhisperProcess(executable:exe,model:model,timeout:10)
  let task = Task { try await client.transcribe(file:audio) }
  for _ in 0..<200 {
   if FileManager.default.fileExists(atPath:model.appendingPathExtension("pid").path) { break }
   try await Task.sleep(nanoseconds:10_000_000)
  }
  XCTAssertTrue(FileManager.default.fileExists(atPath:model.appendingPathExtension("pid").path))
  do { _ = try await client.transcribe(file:audio); XCTFail("overlap must throw") } catch {}
  task.cancel()
  do { _ = try await task.value; XCTFail("cancel must throw") } catch { XCTAssertTrue(error is CancellationError) }
  let pid = try String(contentsOf:model.appendingPathExtension("pid")).trimmingCharacters(in:.whitespacesAndNewlines)
  XCTAssertEqual(Darwin.kill(Int32(pid)!,0),-1)
  XCTAssertEqual(errno,ESRCH)
 }
 func testBothPipesDrainWithoutDeadlock() async throws {
  let (base,exe,model,audio) = try fixture("/usr/bin/awk 'BEGIN { for(i=0;i<20000;i++) { print \"abcdefghijk\"; print \"diagnostics\" > \"/dev/stderr\" } }'\n")
  defer { try? FileManager.default.removeItem(at:base) }
  let text = try await WhisperProcess(executable:exe,model:model,timeout:5).transcribe(file:audio)
  XCTAssertGreaterThan(text.count,200000)
 }
}

extension WhisperProcessTests {
 func testPromptIsLiteralArgumentAndEmptyOutputIsValid() async throws {
  let (base,exe,model,audio) = try fixture("printf '%s' \"${11}\"\n")
  defer { try? FileManager.default.removeItem(at:base) }
  let client = WhisperProcess(executable:exe,model:model)
  let prompt = "$(touch NEVER_EXECUTE); 日本語 'quoted'"
  let text = try await client.transcribe(file:audio,prompt:prompt)
  XCTAssertEqual(text,prompt)
  let empty = try await client.transcribe(file:audio)
  XCTAssertEqual(empty,"")
 }
 func testMissingModelIsNotPreparedAndThrows() async throws {
  let (base,exe,model,audio) = try fixture("echo valid\n")
  defer { try? FileManager.default.removeItem(at:base) }
  try FileManager.default.removeItem(at:model)
  let client = WhisperProcess(executable:exe,model:model)
  let prepared = await client.isPrepared
  XCTAssertFalse(prepared)
  do { _ = try await client.transcribe(file:audio); XCTFail("missing model must throw") } catch {}
 }
}
extension WhisperProcessTests {
 func testLeadingBoundaryWhitespaceIsPreserved() async throws {
  let (base,exe,model,audio) = try fixture("printf ' is ready\\n'\n")
  defer { try? FileManager.default.removeItem(at:base) }
  let text = try await WhisperProcess(executable:exe,model:model).transcribe(file:audio)
  XCTAssertEqual(text," is ready\n")
 }
}

private final class ObservedPID: @unchecked Sendable {
 private let lock = NSLock()
 private var pid: Int32?
 func set(_ value: Int32) { lock.lock(); defer { lock.unlock() }; pid = value }
 var value: Int32? { lock.lock(); defer { lock.unlock() }; return pid }
}
