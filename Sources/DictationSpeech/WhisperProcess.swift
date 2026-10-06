import Foundation
import DictationCore
import Darwin

public actor WhisperProcess {
    private let executable: URL
    private let model: URL
    private let timeout: TimeInterval
    private var running = false
    private var onStarted: (@Sendable (Int32) -> Void)?
    internal func observeProcessStart(_ observer: @escaping @Sendable (Int32) -> Void) { onStarted = observer }
    public init(executable: URL, model: URL, timeout: TimeInterval = 120) {
        self.executable = executable; self.model = model
        self.timeout = timeout.isFinite ? max(0.01, timeout) : 120
    }
    public var isPrepared: Bool {
        FileManager.default.isExecutableFile(atPath: executable.path) &&
        FileManager.default.fileExists(atPath: model.path)
    }
    public func transcribe(file: URL, prompt: String = "") async throws -> String {
        guard !running else { throw DictationError.message("Speech inference is already running") }
        guard isPrepared, FileManager.default.fileExists(atPath: file.path) else {
            throw DictationError.message("Speech executable, model, or input file is missing")
        }
        try Task.checkCancellation()
        running = true
        defer { running = false }
        let worker = WhisperChild(executable: executable, arguments: ["-m", model.path, "-f", file.path,
            "-l", "ja", "-t", "4", "-nt", "--prompt", prompt], timeout: timeout, onStarted: onStarted)
        let result = try await withTaskCancellationHandler(operation: {
            try await Task.detached { try worker.run() }.value
        }, onCancel: { worker.cancel() })
        try Task.checkCancellation()
        return result
    }
}

private final class PipeCapture: @unchecked Sendable {
    private let pipe: Pipe
    private let group = DispatchGroup()
    private var bytes = Data()
    private var oversized = false
    init(_ pipe: Pipe) { self.pipe = pipe }
    func start() {
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { self.group.leave() }
            while true {
                let chunk = self.pipe.fileHandleForReading.readData(ofLength: 65536)
                if chunk.isEmpty { break }
                if self.bytes.count + chunk.count <= 16 * 1024 * 1024 { self.bytes.append(chunk) }
                else { self.oversized = true }
            }
        }
    }
    func finish() -> (Data, Bool) { group.wait(); return (bytes, oversized) }
}

private final class WhisperChild: @unchecked Sendable {
    private let lock = NSLock()
    private let process = Process()
    private let timeout: TimeInterval
    private var cancelled = false
    private let onStarted: (@Sendable (Int32) -> Void)?
    init(executable: URL, arguments: [String], timeout: TimeInterval, onStarted: (@Sendable (Int32) -> Void)?) {
        self.onStarted = onStarted
        process.executableURL = executable; process.arguments = arguments; self.timeout = timeout
    }
    func cancel() {
        lock.lock(); cancelled = true
        if process.isRunning { process.terminate() }
        lock.unlock()
    }
    private func isCancelled() -> Bool {
        lock.lock(); defer { lock.unlock() }; return cancelled
    }
    func run() throws -> String {
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout; process.standardError = stderr
        let output = PipeCapture(stdout), errors = PipeCapture(stderr)
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        do { try process.run() } catch { lock.unlock(); throw error }
        lock.unlock()
        onStarted?(process.processIdentifier)
        output.start(); errors.start()
        let started = ProcessInfo.processInfo.systemUptime
        var timedOut = false
        var stoppingAt: TimeInterval?
        while process.isRunning {
            if isCancelled() || ProcessInfo.processInfo.systemUptime - started >= timeout {
                timedOut = !isCancelled()
                if stoppingAt == nil { stoppingAt = ProcessInfo.processInfo.systemUptime; process.terminate() }
                if let stoppingAt, ProcessInfo.processInfo.systemUptime - stoppingAt > 0.2, process.isRunning {
                    // Only this Process's child PID is signalled, never a process group.
                    Darwin.kill(process.processIdentifier, SIGKILL)
                }
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        process.waitUntilExit()
        // Close parent writers so EOF is guaranteed after the child exits.
        try? stdout.fileHandleForWriting.close(); try? stderr.fileHandleForWriting.close()
        let (data, outputTooLarge) = output.finish()
        let (_, errorsTooLarge) = errors.finish()
        if isCancelled() { throw CancellationError() }
        if timedOut { throw DictationError.message("Speech inference timed out") }
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw DictationError.message("Speech process failed with status \(process.terminationStatus)")
        }
        guard !outputTooLarge, !errorsTooLarge else { throw DictationError.message("Speech output exceeded its size limit") }
        guard let text = String(data: data, encoding: .utf8) else { throw DictationError.message("Speech output is not UTF-8") }
        return text
    }
}
